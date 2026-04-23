<script setup lang="ts">
const runtimeConfig = useRuntimeConfig()

const pageview = ref<number | null>(null)
const startAt = ref(0)
const failed = ref(false)
const loading = ref(true)

const time = useTimeAgo(() => startAt.value)

onMounted(async () => {
  try {
    const data = await $fetch<{ pageview: number, startAt: number }>(`${runtimeConfig.public.apiBaseUrl}/api/pageview`)
    pageview.value = data.pageview
    startAt.value = data.startAt
  }
  catch {
    failed.value = true
  }
  finally {
    loading.value = false
  }
})
</script>

<template>
  <div text-gray:80>
    <template v-if="loading">
      <span op50 italic>Loading API stats...</span>
    </template>
    <template v-else-if="failed">
      <span text-gray>Back-end offline</span>
    </template>
    <template v-else>
      <span text-gray font-500>{{ pageview }}</span>
      page views since
      <span text-gray>{{ time }}</span>
    </template>
  </div>
</template>
