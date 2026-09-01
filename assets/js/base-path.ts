function normalizeBasePath(path: string | null): string {
  if (!path || path === '/') {
    return ''
  }

  return `/${path.replace(/^\/+|\/+$/g, '')}`
}

export function getBasePath(): string {
  const meta = document.querySelector("meta[name='plausible-base-path']")
  return normalizeBasePath(meta?.getAttribute('content') ?? null)
}

export function withBasePath(path: string): string {
  return `${getBasePath()}/${path.replace(/^\/+/, '')}`
}
