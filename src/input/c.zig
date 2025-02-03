pub const c = @cImport({
    // Workarounds to make ZLS work when run from MacOS
    @cDefine("_WIN32", "1");
    @cDefine("__MINGW32__", "1");
    @cDefine("__declspec(x)", "");

    // Includes
    @cInclude("windows.h");
});
