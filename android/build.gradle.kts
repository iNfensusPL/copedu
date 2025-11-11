// android/build.gradle.kts

// Nie definiujemy tu wersji pluginów (są w settings.gradle.kts)

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}
