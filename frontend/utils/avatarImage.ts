export const AVATAR_MAX_SOURCE_BYTES = 2 * 1024 * 1024
export const AVATAR_OUTPUT_SIZE = 512

const supportedTypes = new Set(['image/jpeg', 'image/png', 'image/webp'])

export async function normalizeAvatarImage(file: File): Promise<File> {
  if (file.size > AVATAR_MAX_SOURCE_BYTES) throw new Error('avatar_too_large')
  if (!supportedTypes.has(file.type)) throw new Error('invalid_avatar_format')

  const sourceUrl = URL.createObjectURL(file)

  try {
    const image = new Image()
    image.decoding = 'async'
    image.src = sourceUrl
    await image.decode()

    if (!image.naturalWidth || !image.naturalHeight) throw new Error('invalid_avatar_format')

    const cropSize = Math.min(image.naturalWidth, image.naturalHeight)
    const sourceX = (image.naturalWidth - cropSize) / 2
    const sourceY = (image.naturalHeight - cropSize) / 2
    const canvas = document.createElement('canvas')
    canvas.width = AVATAR_OUTPUT_SIZE
    canvas.height = AVATAR_OUTPUT_SIZE

    const context = canvas.getContext('2d')
    if (!context) throw new Error('avatar_processing_failed')

    context.fillStyle = '#f4eddf'
    context.fillRect(0, 0, AVATAR_OUTPUT_SIZE, AVATAR_OUTPUT_SIZE)
    context.drawImage(
      image,
      sourceX,
      sourceY,
      cropSize,
      cropSize,
      0,
      0,
      AVATAR_OUTPUT_SIZE,
      AVATAR_OUTPUT_SIZE,
    )

    const blob = await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(
        result => result ? resolve(result) : reject(new Error('avatar_processing_failed')),
        'image/jpeg',
        0.88,
      )
    })
    const basename = file.name.replace(/\.[^.]+$/, '') || 'avatar'

    return new File([blob], `${basename}.jpg`, {
      type: 'image/jpeg',
      lastModified: Date.now(),
    })
  } finally {
    URL.revokeObjectURL(sourceUrl)
  }
}
