/**
 * Hands a backup file to the user: the share sheet on phones (where "save to
 * Files" or sending it elsewhere is the natural move), a download elsewhere.
 * Returns how it went so the caller can say so.
 */
export async function saveBackupFile(
  json: string,
  fileName: string,
  env: { navigator?: Navigator; document?: Document; matchMedia?: Window['matchMedia'] } = {
    navigator: globalThis.navigator,
    document: globalThis.document,
    matchMedia: globalThis.matchMedia?.bind(globalThis),
  },
): Promise<'shared' | 'downloaded' | 'cancelled'> {
  const blob = new Blob([json], { type: 'application/json' })
  const file = new File([blob], fileName, { type: 'application/json' })
  const isPhone = env.matchMedia?.('(pointer: coarse)').matches ?? false
  const nav = env.navigator
  if (isPhone && nav?.canShare?.({ files: [file] }) && nav.share) {
    try {
      await nav.share({ files: [file], title: fileName })
      return 'shared'
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return 'cancelled'
      // Sharing failed for another reason; fall back to a download.
    }
  }
  const doc = env.document!
  const url = URL.createObjectURL(blob)
  const link = doc.createElement('a')
  link.href = url
  link.download = fileName
  link.hidden = true
  doc.body.append(link)
  link.click()
  link.remove()
  setTimeout(() => URL.revokeObjectURL(url), 0)
  return 'downloaded'
}
