/// Import C functions only once
pub const c = @cImport({
    // Workarounds to make ZLS work when run from MacOS
    @cDefine("_WIN32", "1");
    @cDefine("__MINGW32__", "1");
    @cDefine("__declspec(x)", "");

    // Includes
    @cInclude("dxgi1_2.h");
    @cInclude("d3d11.h");
});
