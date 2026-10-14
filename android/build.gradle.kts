allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter 工具固定到 <repo>/build/<module> 查找构建产物；
// Gradle 9 的 Directory.dir() 相对当前 buildDirectory（android/build）解析，
// 因此要上两级（android/build/../../build）才等于仓库根下的 build 目录。
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
