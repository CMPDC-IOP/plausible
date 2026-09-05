import React from 'react'
import {
  render,
  screen,
  waitFor,
  fireEvent,
  waitForElementToBeRemoved
} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { TestContextProviders } from '../../../test-utils/app-context-providers'
import { TopBar } from './top-bar'
import { MockAPI } from '../../../test-utils/mock-api'
import { apiPath } from '../util/url'
import {
  mockAnimationsApi,
  mockResizeObserver,
  mockIntersectionObserver
} from 'jsdom-testing-mocks'

mockAnimationsApi()
mockResizeObserver()
mockIntersectionObserver()

const domain = 'dummy.site'

let mockAPI: MockAPI

beforeAll(() => {
  mockAPI = new MockAPI().start()
})

afterAll(() => {
  mockAPI.stop()
})

beforeEach(() => {
  mockAPI.clear()
  mockAPI.get('/api/sites', { data: [{ domain }] })
})

test('user can open and close site switcher', async () => {
  mockAPI.get('/api/sites', {
    data: [
      domain,
      'example.com',
      'blog.example.com',
      'nested.example.com/path',
      'aççented.ca'
    ].map((domain) => ({
      domain
    }))
  })

  render(<TopBar showCurrentVisitors={false} />, {
    wrapper: (props) => (
      <TestContextProviders siteOptions={{ domain }} {...props} />
    )
  })

  const toggleSiteSwitcher = screen.getByRole('button', { name: domain })
  expect(toggleSiteSwitcher.querySelector('img')).toHaveAttribute(
    'src',
    '/favicon/sources/dummy.site'
  )

  fireEvent.error(toggleSiteSwitcher.querySelector('img')!)
  expect(toggleSiteSwitcher.querySelector('img')).toHaveAttribute(
    'src',
    '/favicon/sources/dummy.site'
  )

  await userEvent.click(toggleSiteSwitcher)
  expect(
    screen
      .queryAllByRole('link')
      .map((el) => ({ text: el.textContent, href: el.getAttribute('href') }))
  ).toEqual(
    [
      { text: ['Back to sites'], href: '/sites' },
      { text: ['Site settings'], href: `/${domain}/settings/general` },
      { text: ['dummy.site', '1'], href: '#' },
      { text: ['example.com', '2'], href: `/example.com` },
      { text: ['blog.example.com', '3'], href: `/blog.example.com` },
      {
        text: ['nested.example.com/path', '4'],
        href: '/nested.example.com~path'
      },
      { text: ['aççented.ca', '5'], href: `/a%C3%A7%C3%A7ented.ca` }
    ].map((l) => ({ ...l, text: l.text.join('') }))
  )

  expect(screen.queryByTestId('sitemenu')).toBeInTheDocument()
  await userEvent.click(toggleSiteSwitcher)
  expect(screen.queryByTestId('sitemenu')).not.toBeInTheDocument()
  expect(screen.queryAllByRole('menuitem')).toEqual([])
})

test('site switcher uses the route token for nested site favicons and settings', async () => {
  const nestedDomain = 'nested.example.com/path'

  render(<TopBar showCurrentVisitors={false} />, {
    wrapper: (props) => (
      <TestContextProviders siteOptions={{ domain: nestedDomain }} {...props} />
    )
  })

  const toggleSiteSwitcher = screen.getByRole('button', {
    name: nestedDomain
  })
  expect(toggleSiteSwitcher.querySelector('img')).toHaveAttribute(
    'src',
    '/favicon/sources/nested.example.com~path'
  )

  await userEvent.click(toggleSiteSwitcher)
  expect(screen.getByRole('link', { name: 'Site settings' })).toHaveAttribute(
    'href',
    '/nested.example.com~path/settings/general'
  )
})

test('site switcher links to a site needing verification with verify_installation and flow params', async () => {
  mockAPI.get('/api/sites', {
    data: [
      { domain, needs_verification: false },
      { domain: 'example.com', needs_verification: true }
    ]
  })

  render(<TopBar showCurrentVisitors={false} />, {
    wrapper: (props) => (
      <TestContextProviders siteOptions={{ domain }} {...props} />
    )
  })

  const toggleSiteSwitcher = screen.getByRole('button', { name: domain })
  await userEvent.click(toggleSiteSwitcher)

  expect(screen.getByRole('link', { name: /example\.com/ })).toHaveAttribute(
    'href',
    '/example.com?verify_installation=true&flow=provisioning'
  )
})

test('user can open and close filters dropdown', async () => {
  render(<TopBar showCurrentVisitors={false} />, {
    wrapper: (props) => (
      <TestContextProviders siteOptions={{ domain }} {...props} />
    )
  })

  const toggleFilters = screen.getByRole('button', { name: 'Filter' })
  await userEvent.click(toggleFilters)
  expect(screen.queryAllByRole('link').map((el) => el.textContent)).toEqual([
    'Page',
    'Hostname',
    'Source',
    'UTM tags',
    'Location',
    'Screen size',
    'Browser',
    'Operating system',
    'Goal'
  ])
  await userEvent.click(toggleFilters)
  expect(screen.queryByTestId('filtermenu')).not.toBeInTheDocument()
  expect(screen.queryAllByRole('link')).toEqual([])
})

test('current visitors renders when visitors are present and disappears after visitors are null', async () => {
  mockAPI.get(apiPath({ domain }, '/current-visitors'), 500)
  render(<TopBar showCurrentVisitors={true} />, {
    wrapper: (props) => (
      <TestContextProviders siteOptions={{ domain }} {...props} />
    )
  })

  await waitFor(() => {
    expect(
      screen.queryByRole('link', { name: /500 current visitors/ })
    ).toBeVisible()
  })

  mockAPI.get(apiPath({ domain }, '/current-visitors'), null)
  fireEvent(document, new CustomEvent('tick'))
  await waitForElementToBeRemoved(() =>
    screen.queryByRole('link', { name: /current visitors/ })
  )
})
