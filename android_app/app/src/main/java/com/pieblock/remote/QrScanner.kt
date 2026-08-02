package com.pieblock.remote

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.media.Image
import android.util.Log
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.zxing.BinaryBitmap
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.multi.qrcode.QRCodeMultiReader
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/// 使用 CameraX + ZXing 扫描二维码，解析 ws:// 地址
class QrScanner(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val previewView: PreviewView,
    private val onResult: (String) -> Unit
) {
    companion object {
        private const val TAG = "QrScanner"
        const val CAMERA_PERMISSION_REQUEST = 1001
    }

    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private val qrReader = QRCodeMultiReader()
    private var scanning = false

    fun start() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            if (context is Activity) {
                ActivityCompat.requestPermissions(
                    context,
                    arrayOf(Manifest.permission.CAMERA),
                    CAMERA_PERMISSION_REQUEST
                )
            }
            return
        }
        startCamera()
    }

    fun stop() {
        scanning = false
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }
            val imageAnalyzer = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { it.setAnalyzer(cameraExecutor, ::analyzeImage) }
            val selector = CameraSelector.DEFAULT_BACK_CAMERA
            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    lifecycleOwner, selector, preview, imageAnalyzer
                )
                scanning = true
            } catch (e: Exception) {
                Log.e(TAG, "Camera bind failed", e)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun analyzeImage(image: ImageProxy) {
        if (!scanning) {
            image.close()
            return
        }
        try {
            val plane = image.planes[0]
            val buffer = plane.buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            val width = image.width
            val height = image.height
            val source = PlanarYUVLuminanceSource(
                bytes, width, height, 0, 0, width, height, false
            )
            val bitmap = BinaryBitmap(HybridBinarizer(source))
            val results = qrReader.decodeMultiple(bitmap)
            for (result in results) {
                val text = result.text
                if (text.startsWith("ws://") || text.startsWith("http://")) {
                    scanning = false
                    onResult(text)
                    break
                }
            }
        } catch (e: Exception) {
            // No QR found in this frame, continue
        } finally {
            image.close()
        }
    }
}
