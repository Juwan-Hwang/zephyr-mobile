package com.zephyr.engine

/**
 * Built-in app catalogue (core-mobile `appId`s, contract §14). Names are what the UI shows ("GPT", "Gemini");
 * [kind] is the scene that carries the app by default.
 */
data class AppInfo(val id: String, val name: String, val kind: SceneKind, val keywords: List<String>)

object Apps {
    val ALL: List<AppInfo> = listOf(
        AppInfo("chatgpt", "GPT", SceneKind.AI, listOf("chatgpt", "gpt", "openai")),
        AppInfo("claude", "Claude", SceneKind.AI, listOf("claude", "anthropic")),
        AppInfo("gemini", "Gemini", SceneKind.AI, listOf("gemini", "谷歌ai")),
        AppInfo("perplexity", "Perplexity", SceneKind.AI, listOf("perplexity")),
        AppInfo("grok", "Grok", SceneKind.AI, listOf("grok")),
        AppInfo("netflix", "Netflix", SceneKind.VIDEO, listOf("netflix", "奈飞", "网飞")),
        AppInfo("youtube", "YouTube", SceneKind.VIDEO, listOf("youtube", "油管")),
        AppInfo("disney", "Disney+", SceneKind.VIDEO, listOf("disney+", "disney", "迪士尼")),
        AppInfo("max", "Max", SceneKind.VIDEO, listOf("hbo max", "hbo")),
        AppInfo("primevideo", "Prime Video", SceneKind.VIDEO, listOf("prime video", "primevideo")),
    )
    private val byId = ALL.associateBy { it.id }
    fun byId(id: String): AppInfo? = byId[id]
    fun name(id: String): String = byId[id]?.name ?: id
}
