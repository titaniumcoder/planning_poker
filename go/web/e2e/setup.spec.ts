import { expect, test } from '@playwright/test';

test('loads the embedded application and connects in real time', async ({ page }) => {
  const browserErrors: string[] = [];
  page.on('pageerror', (error) => browserErrors.push(error.message));

  await page.goto('/');

  await expect(
    page.getByRole('heading', { name: 'Planning poker, rebuilt for speed.' }),
  ).toBeVisible();
  await expect(page.getByTestId('connection-status')).toHaveText('Connected');
  expect(browserErrors).toEqual([]);
});
