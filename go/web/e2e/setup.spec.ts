import { expect, test } from '@playwright/test';

test('loads the embedded application and connects in real time', async ({ page }) => {
  const browserErrors: string[] = [];
  page.on('pageerror', (error) => browserErrors.push(error.message));

  await page.goto('/');

  await expect(
    page.getByRole('heading', { name: 'Make the next estimate together.' }),
  ).toBeVisible();
  await expect(page.getByTestId('connection-status')).toHaveText('Connected');
  expect(browserErrors).toEqual([]);
});

test('exposes an accessible foundation surface', async ({ page }) => {
  await page.goto('/');

  await expect(page).toHaveTitle('Planning Poker');
  await expect(page.getByRole('navigation', { name: 'Primary navigation' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Planning Poker home' })).toHaveAttribute(
    'href',
    '/',
  );
  await expect(
    page.getByRole('heading', { name: 'Make the next estimate together.' }),
  ).toBeVisible();
  await expect(page.getByRole('form', { name: 'Create session' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Create planning poker' })).toBeVisible();
  await expect(page.locator('footer')).toContainText('Estimate together');
});

test('keeps the connection status live and free of browser errors', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('/');

  const status = page.getByRole('status');
  await expect(status).toHaveAttribute('aria-live', 'polite');
  await expect(status).toContainText('Connected');
  expect(errors).toEqual([]);
});
