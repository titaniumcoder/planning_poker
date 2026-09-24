import { cleanup, render, screen } from '@testing-library/svelte';
import { afterEach, describe, expect, it, vi } from 'vitest';
import App from './App.svelte';

const realtimeMock = vi.hoisted(() => ({
  value: { phase: 'connected' as 'connected' | 'offline', attempts: 0 },
  subscribers: new Set<(value: { phase: 'connected' | 'offline'; attempts: number }) => void>(),
  phase: {
    subscribe(run: (value: { phase: 'connected' | 'offline'; attempts: number }) => void) {
      realtimeMock.subscribers.add(run);
      run(realtimeMock.value);
      return () => realtimeMock.subscribers.delete(run);
    },
    set(value: { phase: 'connected' | 'offline'; attempts: number }) {
      realtimeMock.value = value;
      realtimeMock.subscribers.forEach((run) => run(value));
    },
  },
  start: vi.fn(),
  stop: vi.fn(),
}));

vi.mock('./lib/realtime/client', () => ({
  RealtimeClient: class {
    state = { subscribe: realtimeMock.phase.subscribe };
    start = realtimeMock.start;
    stop = realtimeMock.stop;
  },
}));

describe('App', () => {
  afterEach(() => {
    cleanup();
    realtimeMock.phase.set({ phase: 'connected', attempts: 0 });
  });

  it('starts realtime on mount and stops it on unmount', () => {
    const view = render(App);

    expect(realtimeMock.start).toHaveBeenCalledOnce();
    view.unmount();
    expect(realtimeMock.stop).toHaveBeenCalledOnce();
  });

  it('announces realtime status and renders the creation flow', () => {
    render(App);

    expect(screen.getByRole('heading', { name: 'Make the next estimate together.' })).toBeVisible();
    expect(screen.getByRole('status')).toHaveTextContent('Connected');
    expect(screen.getByRole('navigation', { name: 'Primary navigation' })).toBeVisible();
    expect(screen.getByRole('link', { name: 'Planning Poker home' })).toHaveAttribute('href', '/');
    expect(screen.getByRole('form', { name: 'Create session' })).toBeVisible();
    expect(screen.getByRole('button', { name: 'Create planning poker' })).toBeVisible();
  });

  it('maps offline state to an accessible live status', () => {
    realtimeMock.phase.set({ phase: 'offline', attempts: 1 });
    render(App);

    expect(screen.getByRole('status')).toHaveTextContent('Offline');
    expect(screen.getByRole('status')).toHaveAttribute('aria-live', 'polite');
  });
});
