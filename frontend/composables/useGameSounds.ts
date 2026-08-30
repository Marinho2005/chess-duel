import { readonly, ref } from 'vue'
import { readSoundPreference, writeSoundPreference } from '~/utils/gameSound'

export type GameSound = 'move' | 'capture' | 'check' | 'gameOver'

export function useGameSounds() {
  const enabled = ref(true)
  let context: AudioContext | null = null

  function restore() {
    if (!import.meta.client) return
    enabled.value = readSoundPreference(localStorage)
  }

  function setEnabled(value: boolean) {
    enabled.value = value
    if (import.meta.client) writeSoundPreference(localStorage, value)
    if (value) unlock()
  }

  function toggle() { setEnabled(!enabled.value) }

  function unlock() {
    if (!import.meta.client || !enabled.value) return
    context ||= new AudioContext()
    if (context.state === 'suspended') void context.resume()
  }

  function play(kind: GameSound) {
    if (!import.meta.client || !enabled.value) return
    unlock()
    if (!context || context.state !== 'running') return

    const patterns: Record<GameSound, Array<[number, number, number, number]>> = {
      move: [[0, .052, .16, 720]],
      capture: [[0, .065, .2, 560], [.048, .058, .16, 430]],
      check: [[0, .052, .17, 760], [.052, .045, .13, 1450]],
      gameOver: [[0, .072, .18, 620], [.075, .075, .15, 480], [.155, .09, .13, 350]]
    }

    for (const [offset, duration, volume, frequency] of patterns[kind]) {
      playWoodImpact(context, context.currentTime + offset, duration, volume, frequency)
    }
  }

  restore()
  return { enabled: readonly(enabled), setEnabled, toggle, unlock, play }
}

function playWoodImpact(context: AudioContext, start: number, duration: number, volume: number, frequency: number) {
  const frameCount = Math.max(1, Math.floor(context.sampleRate * duration))
  const buffer = context.createBuffer(1, frameCount, context.sampleRate)
  const samples = buffer.getChannelData(0)

  for (let index = 0; index < frameCount; index += 1) {
    const envelope = Math.exp(-7 * index / frameCount)
    samples[index] = (Math.random() * 2 - 1) * envelope
  }

  const source = context.createBufferSource()
  const body = context.createBiquadFilter()
  const gain = context.createGain()
  source.buffer = buffer
  body.type = 'bandpass'
  body.frequency.value = frequency
  body.Q.value = .75
  gain.gain.setValueAtTime(volume, start)
  gain.gain.exponentialRampToValueAtTime(.0001, start + duration)
  source.connect(body).connect(gain).connect(context.destination)
  source.start(start)
  source.stop(start + duration)
}
