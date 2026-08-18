import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// ============================================================================
// Kredensial penandatanganan rilis.
//
// Dibaca dari android/key.properties, yang SENGAJA tidak ter-commit — lihat
// android/.gitignore. Berkasnya boleh tidak ada: build debug dan profile tetap
// berjalan tanpanya, dan itu yang menjaga repo tetap bisa dibangun siapa pun.
//
// Yang TIDAK boleh terjadi adalah build RELEASE berhasil tanpa berkas ini,
// karena hasilnya APK bertanda tangan kunci debug yang tampak siap edar.
// Penjaganya ada di bawah, pada blok tasks.matching.
//
// Aturan lengkapnya di RELEASE-ANDROID.md (ter-commit).
// ============================================================================
val berkasKunci = rootProject.file("key.properties")
val kunciRilis = Properties().apply {
    if (berkasKunci.exists()) berkasKunci.inputStream().use { load(it) }
}

android {
    // namespace menentukan paket kelas R yang dihasilkan, dan HARUS cocok dengan
    // deklarasi `package` di MainActivity.kt.
    namespace = "id.smartcommunityrt.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identitas permanen aplikasi. TIDAK BOLEH DIUBAH setelah APK tersebar:
        // Android memperlakukan applicationId berbeda sebagai aplikasi yang
        // berbeda, sehingga setiap warga harus meng-uninstall lebih dulu.
        applicationId = "id.smartcommunityrt.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Bersumber dari pubspec.yaml (`version: 1.1.0+3`), bukan dari bendera
        // --build-name/--build-number. Nilainya harus hidup di berkas yang
        // ter-commit dan ter-review, bukan di local.properties yang gitignored.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Dievaluasi saat konfigurasi, tetapi nilai null hanya menjadi
            // masalah ketika varian release benar-benar dibangun — dan sebelum
            // itu terjadi, penjaga di bawah sudah menghentikannya dengan pesan
            // yang menjelaskan duduk perkaranya.
            keyAlias = kunciRilis.getProperty("keyAlias")
            keyPassword = kunciRilis.getProperty("keyPassword")
            storeFile = kunciRilis.getProperty("storeFile")?.let { file(it) }
            storePassword = kunciRilis.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // TIDAK ADA jalur mundur ke kunci debug. Jalur mundur diam berarti
            // sebuah build rilis bisa BERHASIL dengan kunci debug dan
            // menghasilkan APK yang tampak siap edar — kegagalan yang tidak
            // berbunyi, dan baru ketahuan bila seseorang ingat memeriksa
            // apksigner.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Penjaga yang berbunyi jelas, DAN berbunyi lebih dulu.
//
// Tanpa ini, build release tanpa key.properties gagal dari dalam AGP tanpa
// memberi tahu apa pun tentang penyebabnya maupun cara memperbaikinya.
//
// Diletakkan pada `taskGraph.whenReady`, bukan pada `doFirst` sebuah task.
// Alasannya ditemukan saat mengujinya: `assembleRelease` berjalan SETELAH
// seluruh dependensinya, sehingga `doFirst` di sana baru dieksekusi jauh
// setelah kompilasi resource dan penandatanganan — dan kegagalan yang muncul
// lebih dulu adalah kegagalan lain yang membingungkan. Graf task diperiksa
// sebelum satu pun task dijalankan.
gradle.taskGraph.whenReady {
    val adaRilis = allTasks.any { t ->
        t.name.contains("Release") &&
            (t.name.startsWith("assemble") || t.name.startsWith("bundle") || t.name.startsWith("package"))
    }
    if (adaRilis && !berkasKunci.exists()) {
        throw GradleException(
            "\n\n" +
                "Build RELEASE menuntut android/key.properties, dan berkas itu tidak ada.\n" +
                "\n" +
                "Berkas itu sengaja TIDAK ter-commit karena memuat kata sandi keystore.\n" +
                "Cara membuat keystore dan key.properties ada di RELEASE-ANDROID.md.\n" +
                "\n" +
                "JANGAN menandatangani rilis dengan kunci debug. Build debug dan profile\n" +
                "tetap berjalan tanpa berkas ini; hanya release yang menuntutnya.\n"
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
