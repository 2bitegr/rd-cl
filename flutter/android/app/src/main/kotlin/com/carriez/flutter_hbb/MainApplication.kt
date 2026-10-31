package com.carriez.flutter_hbb

import android.app.Application
import android.util.Log
import ffi.FFI

class MainApplication : Application() {
    // Called through the already registered application context, including
    // outgoing-only mode where no screen-capture service is running.
    fun officeUnprotect(value: String): String = try { OfficeSecureStore.unprotect(value) } catch (_: Exception) { "" }
    companion object {
        private const val TAG = "MainApplication"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "App start")
        FFI.onAppStart(applicationContext)
    }
}
