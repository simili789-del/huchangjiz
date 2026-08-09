package com.huochang.yard.util

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

/**
 * Writes exported text (CSV or JSON) into the app cache and shares it via a
 * FileProvider-backed intent (replaces the PWA's in-browser download).
 */
object FileSharer {

    fun shareText(context: Context, fileName: String, content: String, mime: String) {
        val cacheDir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(cacheDir, fileName)
        file.writeText(content)

        val uri: Uri = FileProvider.getUriForFile(
            context,
            context.packageName + ".fileprovider",
            file
        )

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "导出文件"))
    }
}
