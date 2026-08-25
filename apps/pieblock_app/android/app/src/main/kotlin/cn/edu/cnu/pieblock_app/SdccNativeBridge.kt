package cn.edu.cnu.pieblock_app

internal object SdccNativeBridge {
    init {
        System.loadLibrary("pieblock_sdcc_native")
    }

    external fun apiVersion(): Int
    external fun fingerprint(): String
    external fun isAvailable(): Boolean
    external fun start(
        workingDirectory: String,
        resourceDirectory: String,
        projectKind: String,
        mainSourcePath: String,
        interruptHeaderPath: String,
        sourcePaths: Array<String>,
        librarySourcePaths: Array<String>,
        compileArguments: Array<String>,
        linkArguments: Array<String>,
        hexOutputPath: String,
        mapOutputPath: String,
        logOutputPath: String,
    ): Long
    external fun poll(handle: Long): Array<String>?
    external fun result(handle: Long): Array<String>?
    external fun cancel(handle: Long)
    external fun destroy(handle: Long)
}
