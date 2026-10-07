local ffi = require("ffi")

ffi.cdef[[
typedef uintptr_t     ULONG_PTR;
typedef unsigned int  UINT;
typedef unsigned int  DWORD;
typedef int           BOOL;
typedef int           Status;
typedef unsigned long long ULONGLONG;

typedef void* GpImage;
typedef void* GpBitmap;

typedef struct {
    UINT GdiplusVersion;
    void* DebugEventCallback;
    BOOL SuppressBackgroundThread;
    BOOL SuppressExternalCodecs;
} GdiplusStartupInput;

typedef struct {
    void* NotificationHook;
    void* NotificationUnhook;
} GdiplusStartupOutput;

typedef struct {
    long X;
    long Y;
    long Width;
    long Height;
} GpRect;

typedef struct {
    UINT Width;
    UINT Height;
    int Stride;
    int PixelFormat;
    void* Scan0;
    UINT Reserved;
} BitmapData;

typedef struct {
    UINT id;
    UINT length;
    unsigned short type;
    void* value;
} PropertyItem;

typedef struct {
    DWORD Data1;
    unsigned short Data2;
    unsigned short Data3;
    unsigned char Data4[8];
} GUID;

ULONGLONG GetTickCount64(void);

/* Native API to create directories silently without popping up cmd.exe */
int SHCreateDirectoryExA(void* hwnd, const char* pszPath, void* psa);

/* Changed ULONG to ULONG_PTR to prevent stack corruption on 64-bit */
Status GdiplusStartup(ULONG_PTR* token, const GdiplusStartupInput* input, GdiplusStartupOutput* output);
void   GdiplusShutdown(ULONG_PTR token);

Status GdipLoadImageFromFile(const uint16_t* filename, void** image);
Status GdipDisposeImage(void* image);

Status GdipImageGetFrameDimensionsCount(void* image, UINT* count);
Status GdipImageGetFrameDimensionsList(void* image, GUID* guids, UINT count);
Status GdipImageGetFrameCount(void* image, const GUID* dimension, UINT* count);
Status GdipImageSelectActiveFrame(void* image, const GUID* dimension, UINT frameIndex);

Status GdipGetImageWidth(void* image, UINT* width);
Status GdipGetImageHeight(void* image, UINT* height);

Status GdipGetPropertyItemSize(void* image, UINT propId, UINT* size);
Status GdipGetPropertyItem(void* image, UINT propId, UINT size, PropertyItem* item);

Status GdipSaveImageToFile(void* image, const uint16_t* filename, const GUID* clsidEncoder, const void* encoderParams);
]]

local gdiplus = ffi.load("gdiplus")
local k32 = ffi.load("kernel32")
local shell32 = ffi.load("shell32")

local gif = {
    started = false,
    token = nil,
    cache_dir = "C:\\Echidna-L4d2\\gif_cache\\",
    cache = {}, -- [gif_path] = anim
    default_delay_ms = 60,
}

local FrameDimTime = ffi.new("GUID", {
    Data1 = 0x6AEDBD6D,
    Data2 = 0x3FB5,
    Data3 = 0x418A,
    Data4 = {0x83, 0xA6, 0x7F, 0x45, 0x22, 0x9D, 0xC8, 0x72}
})

-- BMP encoder CLSID
local BmpEncoder = ffi.new("GUID", {
    Data1 = 0x557CF400,
    Data2 = 0x1A04,
    Data3 = 0x11D3,
    Data4 = {0x9A, 0x73, 0x00, 0x00, 0xF8, 0x1E, 0xF3, 0x2E}
})

local function ensure_dir(path)
    shell32.SHCreateDirectoryExA(nil, path, nil)
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function sanitize_key(path)
    return (path:gsub("[^%w]+", "_"))
end

local function to_wide(s)
    local buf = ffi.new("uint16_t[?]", #s + 1)
    for i = 1, #s do
        buf[i - 1] = s:byte(i)
    end
    buf[#s] = 0
    return buf
end

local function now_ms()
    return tonumber(k32.GetTickCount64())
end

local function init_gdiplus()
    if gif.started then
        return true
    end

    local input = ffi.new("GdiplusStartupInput")
    input.GdiplusVersion = 1
    input.SuppressBackgroundThread = 0
    input.SuppressExternalCodecs = 0

    local token = ffi.new("ULONG_PTR[1]")
    local st = gdiplus.GdiplusStartup(token, input, nil)
    if st ~= 0 then
        return false
    end

    gif.token = token[0]
    gif.started = true
    return true
end

local function get_frame_delays(image, frame_count)
    local delays = {}
    local size = ffi.new("UINT[1]")

    local st = gdiplus.GdipGetPropertyItemSize(image, 0x5100, size)
    if st ~= 0 or size[0] == 0 then
        for i = 1, frame_count do
            delays[i] = gif.default_delay_ms
        end
        return delays
    end

    local buf_size = math.ceil(size[0] / 8)
    local buf = ffi.new("uint64_t[?]", buf_size)
    
    st = gdiplus.GdipGetPropertyItem(image, 0x5100, size[0], ffi.cast("PropertyItem*", buf))
    if st ~= 0 then
        for i = 1, frame_count do
            delays[i] = gif.default_delay_ms
        end
        return delays
    end

    local item = ffi.cast("PropertyItem*", buf)
    local values = ffi.cast("uint32_t*", item.value)
    local count = tonumber(item.length / 4)

    for i = 0, frame_count - 1 do
        local v = 0
        if i < count then
            v = tonumber(values[i]) or 0
        end

        local ms = v * 10
        if ms < 20 then
            ms = gif.default_delay_ms
        end
        delays[i + 1] = ms
    end

    return delays
end

local function load_frame_texture(anim_dir, image, frame_index, dims)
    local frame_path = anim_dir .. string.format("%04d.bmp", frame_index + 1)
    if not file_exists(frame_path) then
        local st = gdiplus.GdipSaveImageToFile(image, to_wide(frame_path), BmpEncoder, nil)
        if st ~= 0 then
            return nil
        end
    end

    if client and client.load_texture then
        return client.load_texture(frame_path)
    end

    return nil
end

local function load_gif(path)
    if gif.cache[path] then
        return gif.cache[path]
    end

    if not init_gdiplus() then
        return nil
    end

    ensure_dir(gif.cache_dir)

    local image_ptr = ffi.new("void*[1]")
    local st = gdiplus.GdipLoadImageFromFile(to_wide(path), image_ptr)
    if st ~= 0 or image_ptr[0] == nil then
        return nil
    end

    local image = image_ptr[0]

    local dim_count = ffi.new("UINT[1]")
    st = gdiplus.GdipImageGetFrameDimensionsCount(image, dim_count)
    if st ~= 0 or dim_count[0] == 0 then
        gdiplus.GdipDisposeImage(image)
        return nil
    end

    local dims = ffi.new("GUID[?]", dim_count[0])
    st = gdiplus.GdipImageGetFrameDimensionsList(image, dims, dim_count[0])
    if st ~= 0 then
        gdiplus.GdipDisposeImage(image)
        return nil
    end

    local frame_count_u = ffi.new("UINT[1]")
    st = gdiplus.GdipImageGetFrameCount(image, dims, frame_count_u)
    if st ~= 0 or frame_count_u[0] == 0 then
        gdiplus.GdipDisposeImage(image)
        return nil
    end

    local frame_count = tonumber(frame_count_u[0])
    local delays = get_frame_delays(image, frame_count)

    local width_u = ffi.new("UINT[1]")
    local height_u = ffi.new("UINT[1]")
    gdiplus.GdipGetImageWidth(image, width_u)
    gdiplus.GdipGetImageHeight(image, height_u)

    local anim_key = sanitize_key(path)
    local anim_dir = gif.cache_dir .. anim_key .. "\\"
    ensure_dir(anim_dir)

    local textures = {}

    for i = 0, frame_count - 1 do
        gdiplus.GdipImageSelectActiveFrame(image, dims, i)
        local tex = load_frame_texture(anim_dir, image, i, dims)
        if tex then
            textures[#textures + 1] = tex
        end
    end

    gdiplus.GdipDisposeImage(image)

    local anim = {
        path = path,
        key = anim_key,
        textures = textures,
        delays = delays,
        start_ms = now_ms(),
        total_ms = 0,
        w = tonumber(width_u[0]),
        h = tonumber(height_u[0]),
    }

    for _, d in ipairs(delays) do
        anim.total_ms = anim.total_ms + d
    end

    if anim.total_ms <= 0 then
        anim.total_ms = #textures * gif.default_delay_ms
    end

    gif.cache[path] = anim
    return anim
end

function gif.init(cache_dir)
    if cache_dir and cache_dir ~= "" then
        gif.cache_dir = cache_dir
    end
    ensure_dir(gif.cache_dir)
    return init_gdiplus()
end

function gif.texture(path)
    local anim = load_gif(path)
    if not anim or #anim.textures == 0 then
        return nil
    end

    local elapsed = now_ms() - anim.start_ms
    if anim.total_ms <= 0 then
        return anim.textures[1]
    end

    local t = elapsed % anim.total_ms
    local acc = 0

    for i, d in ipairs(anim.delays) do
        acc = acc + d
        if t < acc then
            return anim.textures[i]
        end
    end

    return anim.textures[#anim.textures]
end

function gif.draw(path, x, y, w, h, rounding)
    local tex = gif.texture(path)
    if not tex then
        return false
    end

    local dl = imgui.get_window_draw_list()
    rounding = rounding or 0

    if rounding > 0 then
        dl:add_image_rounded(tex, x, y, x + w, y + h, 0, 0, 1, 1, 1, 1, 1, 1, rounding)
    else
        dl:add_image_rounded(tex, x, y, x + w, y + h, 0, 0, 1, 1, 1, 1, 1, 1, 0)
    end

    return true
end

function gif.clear()
    for _, anim in pairs(gif.cache) do
        if anim and anim.textures then
            for _, tex in ipairs(anim.textures) do
            end
        end
    end
    gif.cache = {}
end

function gif.shutdown()
    gif.clear()
    if gif.started and gif.token then
        gdiplus.GdiplusShutdown(gif.token)
    end
    gif.started = false
    gif.token = nil
end

function gif.get_size(path)
    local anim = gif.cache[path] or load_gif(path)
    if anim then
        return anim.w, anim.h
    end
    return 0, 0
end

return gif
