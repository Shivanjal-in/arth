import type { Localized } from './notify.js';

const clip = (s: string, n = 90) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);
const who = (name: string, lang: 'en' | 'hi') => name.trim() || (lang === 'hi' ? 'एक पाठक' : 'A reader');

export function commentMessage(name: string, bookTitle: string, text: string, route: string): Localized {
  return (lang) =>
    lang === 'hi'
      ? { title: `“${clip(bookTitle, 40)}” के आपके सार पर टिप्पणी`, body: `${who(name, lang)}: ${clip(text)}`, route }
      : { title: `New comment on your recap of “${clip(bookTitle, 40)}”`, body: `${who(name, lang)}: ${clip(text)}`, route };
}

export function replyMessage(name: string, bookTitle: string, text: string, route: string): Localized {
  return (lang) =>
    lang === 'hi'
      ? { title: `${who(name, lang)} ने आपको जवाब दिया`, body: `“${clip(bookTitle, 40)}” पर: ${clip(text)}`, route }
      : { title: `${who(name, lang)} replied to you`, body: `On “${clip(bookTitle, 40)}”: ${clip(text)}`, route };
}

export function removedMessage(kind: 'deck' | 'comment', title: string): Localized {
  return (lang) =>
    lang === 'hi'
      ? {
          title: kind === 'deck' ? 'आपका सार हटाया गया' : 'आपकी टिप्पणी हटाई गई',
          body: `“${clip(title, 50)}” समुदाय के नियमों के कारण हटाया गया।`,
          route: '/community',
        }
      : {
          title: kind === 'deck' ? 'Your recap was removed' : 'Your comment was removed',
          body: `“${clip(title, 50)}” was removed for breaking the community rules.`,
          route: '/community',
        };
}

export function broadcastMessage(title: string, body: string, route: string | undefined): Localized {
  return () => ({ title, body, ...(route ? { route } : {}), tag: 'broadcast' });
}
