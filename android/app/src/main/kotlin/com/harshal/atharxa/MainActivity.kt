package com.harshal.atharxa

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity): Health Connect's permission
// screen needs registerForActivityResult. The one approved native-code change.
class MainActivity : FlutterFragmentActivity()
