import { render, screen } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import App from './App.svelte';

vi.mock('./lib/realtime/client', () => ({
  RealtimeClient: class {
    state = {
      subscribe(run: (value: { phase: 'connected'; attempts: number }) => void) {
        run({ phase: 'connected', attempts: 0 });
        return () => undefined;
      },
    };
    start = vi.fn();
    stop = vi.fn();
  },
}));

describe('App', () => {
  it('announces realtime status and renders the setup surface', () => {
    render(App);

    expect(
      screen.getByRole('heading', { name: 'Planning poker, rebuilt for speed.' }),
    ).toBeVisible();
    expect(screen.getByRole('status')).toHaveTextContent('Connected');
  });
});
