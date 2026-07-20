allprojects {
    repositories {
        google()
        mavenCentral()
        // Mapbox Maps SDK binaries (secret downloads token; never commit the value).
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication {
                create<BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password = System.getenv("SDK_REGISTRY_TOKEN")
                    ?: System.getenv("MAPBOX_DOWNLOADS_TOKEN")
                    ?: (project.findProperty("SDK_REGISTRY_TOKEN") as String?)
                    ?: (project.findProperty("MAPBOX_DOWNLOADS_TOKEN") as String?)
                    ?: ""
            }
        }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
