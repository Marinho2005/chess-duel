<template>
  <div class="app-layout">
    <NavigationAppHeader />
    <div class="page-content">
      <slot />
    </div>
  </div>
</template>

<style scoped>
.app-layout {
  min-height: 100vh;
  background: var(--bg);
}

.page-content { min-width: 0; }

</style>
