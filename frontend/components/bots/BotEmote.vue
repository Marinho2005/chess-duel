<script setup lang="ts">
defineProps<{ persona: string; name: string; size?: 'small' | 'large' }>()
</script>

<template>
  <span class="emote" :class="[persona, size || 'large']" :style="size === 'small' ? { zoom: 'var(--bot-emote-scale, 1)' } : undefined" role="img" :aria-label="`Personagem de ${name}`">
    <i class="hair" aria-hidden="true" />
    <i class="face" aria-hidden="true"><b class="eye left" /><b class="eye right" /><b class="mouth" /></i>
    <i class="detail" aria-hidden="true" />
  </span>
</template>

<style scoped>
.emote { --skin: #efb77f; --hair: #573929; --accent: #6f8a58; position: relative; display: inline-grid; width: 92px; height: 92px; place-items: center; overflow: hidden; background: color-mix(in srgb, var(--accent) 22%, #fff5e5); border: 2px solid color-mix(in srgb, var(--accent) 55%, #d4bda0); border-radius: 30% 30% 42% 42%; box-shadow: inset 0 -10px 18px #5c3d2320, 0 8px 18px #6f452820; }
.face { position: absolute; top: 24px; width: 58px; height: 57px; background: var(--skin); border: 2px solid #5b3e2d; border-radius: 46% 46% 42% 42%; }
.hair { position: absolute; top: 13px; z-index: 2; width: 62px; height: 29px; background: var(--hair); border-radius: 55% 55% 30% 20%; transform: rotate(-4deg); }
.eye { position: absolute; top: 22px; width: 7px; height: 8px; background: #30251f; border-radius: 50%; }.eye.left { left: 13px; }.eye.right { right: 13px; }
.mouth { position: absolute; bottom: 10px; left: 20px; width: 17px; height: 7px; border-bottom: 3px solid #713d32; border-radius: 50%; }
.detail { position: absolute; z-index: 4; }
.explorer { --accent: #72a56a; }.explorer .hair { clip-path: polygon(0 35%, 18% 0, 30% 32%, 47% 0, 62% 35%, 82% 4%, 100% 48%, 95% 100%, 5% 100%); }.explorer .detail { top: 8px; right: 9px; width: 22px; height: 17px; background: #d7973d; border: 2px solid #5b3e2d; border-radius: 50% 50% 15% 15%; transform: rotate(18deg); }
.chill { --skin: #c98258; --hair: #332721; --accent: #6e91b1; }.chill .eye { height: 3px; border-radius: 5px; }.chill .mouth { width: 20px; border-bottom-width: 2px; }.chill .detail { top: 42px; width: 55px; height: 13px; border-top: 4px solid #4c3327; border-radius: 50%; }
.focused { --skin: #d59a66; --hair: #39291f; --accent: #b37a4d; }.focused .eye { top: 20px; border-radius: 1px; }.focused .mouth { width: 15px; height: 2px; border-radius: 0; }.focused .detail { top: 39px; width: 46px; height: 12px; border-top: 3px solid #493026; transform: rotate(-3deg); }
.master { --skin: #d7a57a; --hair: #e8e0d4; --accent: #836a9c; }.master .hair { height: 35px; }.master .detail { top: 65px; width: 39px; height: 26px; background: #eee6da; border: 2px solid #5b3e2d; border-top: 0; border-radius: 0 0 50% 50%; }.master .mouth { z-index: 5; }
.robot { --accent: #a64337; background: radial-gradient(circle at 50% 30%, #716e69, #272725); border-color: #a64a3d; border-radius: 24px; }.robot .face { top: 20px; width: 62px; height: 60px; background: linear-gradient(145deg, #c6c3ba, #686a68); border-color: #242525; border-radius: 14px; }.robot .hair { top: 9px; width: 8px; height: 18px; background: #b94a3b; border: 2px solid #272727; border-radius: 4px; }.robot .eye { width: 10px; height: 7px; background: #ff4a35; border-radius: 2px; box-shadow: 0 0 8px #ff301a; }.robot .mouth { bottom: 9px; left: 16px; width: 27px; height: 6px; border: 2px solid #292929; border-width: 2px 0; border-radius: 0; }.robot .detail { top: 47px; width: 72px; height: 3px; background: #292929; }
.small { width: 46px; height: 46px; border-width: 1px; border-radius: 14px; box-shadow: none; transform-origin: center; }.small .face { top: 11px; width: 31px; height: 30px; border-width: 1px; }.small .hair { top: 6px; width: 33px; height: 16px; }.small .eye { top: 11px; width: 4px; height: 4px; }.small .eye.left { left: 7px; }.small .eye.right { right: 7px; }.small .mouth { bottom: 5px; left: 10px; width: 10px; height: 4px; border-bottom-width: 2px; }.small .detail { display: none; }.small.robot .face { top: 9px; width: 33px; height: 32px; border-radius: 7px; }.small.robot .hair { top: 3px; width: 5px; height: 10px; }.small.robot .eye { width: 5px; height: 4px; }.small.robot .mouth { bottom: 5px; left: 8px; width: 15px; height: 4px; }
</style>
