allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// permission_handler_android 14.1.1 declares `compileSdk = 37` and uses API 37 symbols, but the SDK
// publishes API 37 as the platform "android-37.0", which AGP cannot resolve from the plain integer
// ("Failed to find target with hash string 'android-37'"). Point that plugin at the installed
// platform by its full hash string instead.
subprojects {
    if (name == "permission_handler_android") {
        afterEvaluate {
            val android = extensions.getByName("android")
            val setter = android.javaClass.methods.first {
                it.name == "compileSdkVersion" && it.parameterCount == 1 && it.parameterTypes[0] == String::class.java
            }
            setter.invoke(android, "android-37.0")
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
