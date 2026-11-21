<script setup lang="ts">
import type { CommandPart } from './command'

withDefaults(
  defineProps<{
    parts: CommandPart[]
    /** Show as an example: a sunken block that scrolls sideways instead of wrapping. */
    block?: boolean
  }>(),
  { block: false },
)
</script>

<template>
  <code :class="['command-line', 'mono', { 'command-line--block': block }]"
    ><template v-for="(part, i) in parts" :key="i"
      ><template v-if="i > 0">{{ ' ' }}</template
      ><span
        v-if="part.kind === 'blank'"
        class="part part--blank"
        role="img"
        aria-label="blank"
      ></span
      ><span
        v-else
        :class="['part', `part--${part.kind}`, { 'mono-casual': part.kind === 'arg' }]"
        >{{ part.text }}</span
      ></template
    ></code
  >
</template>

<style scoped>
.command-line {
  color: var(--color-text);
  overflow-wrap: anywhere;
}

.command-line--block {
  display: block;
  padding: var(--space-3) var(--space-4);
  border-radius: var(--radius-code);
  background: var(--color-sunken);
  font-size: var(--text-sm);
  line-height: var(--line-height);
  white-space: pre;
  overflow-x: auto;
  overflow-wrap: normal;
}

.part--flag {
  color: var(--color-accent);
  font-weight: 600;
}

.part--arg {
  color: var(--color-arg);
}

.part--blank {
  display: inline-block;
  min-width: 3ch;
  height: 1em;
  border-bottom: 2px dashed var(--color-accent);
  vertical-align: baseline;
}
</style>
