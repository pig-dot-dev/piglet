pub const c = @cImport({
    // Workarounds to make ZLS work when run from MacOS
    @cDefine("_WIN32", "1");
    @cDefine("__MINGW32__", "1");
    @cDefine("__declspec(x)", "");
    @cDefine("__attribute__(x)", "");

    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
    @cInclude("libavdevice/avdevice.h");
    @cInclude("libswscale/swscale.h");
    @cInclude("libavutil/imgutils.h");
});
