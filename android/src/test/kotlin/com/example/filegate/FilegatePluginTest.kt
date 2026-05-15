package com.example.filegate

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

internal class FilegatePluginTest {
    @Test
    fun onMethodCall_getFileSizeWithMissingPath_returnsInvalidArgs() {
        val plugin = FilegatePlugin()

        val call = MethodCall("getFileSize", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "invalid_args",
            "A non-empty file path is required.",
            null
        )
    }
}
