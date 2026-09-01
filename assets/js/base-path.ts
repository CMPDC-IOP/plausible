function normalizeBasePath(path: string | null): string {
  if (!path || path === '/') {
    return ''
  }

  return `/${path.replace(/^\/+|\/+$/g, '')}`
}

let cachedBasePath: string | undefined

export function getBasePath(): string {
  if (cachedBasePath === undefined) {
    const meta = document.querySelector("meta[name='plausible-base-path']")
    cachedBasePath = normalizeBasePath(meta?.getAttribute('content') ?? null)
  }

  return cachedBasePath
}

// The base path is fixed for the lifetime of the page; tests reset it between
// cases because they swap the meta tag.
export function resetBasePathCache(): void {
  cachedBasePath = undefined
}

export function withBasePath(path: string): string {
  return `${getBasePath()}/${path.replace(/^\/+/, '')}`
}
