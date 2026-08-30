<template>
  <div class="app-layout">
    <AppSidebar />
    <div class="page-content">
      <slot />
    </div>
  </div>
</template>

<style scoped>
.app-layout {
  --sidebar-width: 264px;
  display: grid;
  grid-template-columns: var(--sidebar-width) minmax(0, 1fr);
  min-height: 100vh;
  background: #f4eddf;
}

.page-content { min-width: 0; }

@media (max-width: 760px) {
  .app-layout { grid-template-columns: 1fr; }
}
</style>
