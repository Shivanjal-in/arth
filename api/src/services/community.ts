/**
 * The community: readers publish their recap of a book (a deck of cards),
 * others browse, like, save a copy into their own Cards, and comment.
 *
 * Rules (decided 2026-09-26):
 *   - Only Pro and Super readers publish decks; anyone signed in likes,
 *     saves, comments and reports; everyone browses.
 *   - Things go live at once. Readers report; three reports hide an item
 *     until an admin removes it or dismisses the reports.
 *   - Banned readers can still read and save, but not publish, comment or
 *     report.
 */
import { ApiError } from '../lib/errors.js';
import type { User } from './accounts.js';

export type Status = 'live' | 'hidden' | 'removed';

export type DeckCard = {
  kind: 'idea' | 'quote' | 'word';
  front: string;
  back: string;
  note: string;
  /** "Chapter 3" — where in the book, as the author's copy had it. */
  location: string | null;
};

/** The typeface the author chose for their cards; readers see it too. */
export const DECK_FONTS = ['montserrat', 'quintessential', 'bricolage'] as const;
export type DeckFont = (typeof DECK_FONTS)[number];

export type Deck = {
  id: string;
  owner: string;
  /** The author's own title for their recap ("What stayed with me"). */
  title: string;
  bookTitle: string;
  /** Content fingerprint of the author's copy; a saved deck attaches to the same book. */
  bookKey: string | null;
  blurb: string;
  /** Absent on decks published before fonts: Montserrat. */
  font?: DeckFont;
  cards: DeckCard[];
  /** cards.length, stored: lists fetch only a preview of the cards. */
  cardCount: number;
  likes: number;
  saves: number;
  comments: number;
  status: Status;
  reports: number;
  createdAt: number;
  updatedAt: number;
};

export type Comment = {
  id: string;
  deckId: string;
  owner: string;
  /** A reply to this comment (one level: replies don't nest further). */
  parentId: string | null;
  text: string;
  status: Status;
  reports: number;
  createdAt: number;
};

export type ReportKind = 'deck' | 'comment';

export type Report = {
  id: string;
  kind: ReportKind;
  targetId: string;
  reporter: string;
  reason: string;
  createdAt: number;
  resolvedAt: number | null;
  resolution: 'removed' | 'dismissed' | null;
};

export type DeckQuery = { sort: 'recent' | 'popular'; q?: string | undefined; owner?: string | undefined; page: number; limit: number };

export interface CommunityStore {
  insertDeck(deck: Deck): Promise<void>;
  updateDeck(id: string, set: Partial<Deck>): Promise<Deck | null>;
  findDeck(id: string): Promise<Deck | null>;
  /** Live decks only. */
  listDecks(query: DeckQuery): Promise<Deck[]>;
  /** Adds or removes [uid]'s like; returns the new state and count. */
  toggleLike(deckId: string, uid: string): Promise<{ liked: boolean; likes: number }>;
  likedBy(uid: string, deckIds: string[]): Promise<Set<string>>;
  /** Counts [uid]'s save once, however many times they save. */
  addSave(deckId: string, uid: string): Promise<number>;
  insertComment(comment: Comment): Promise<void>;
  updateComment(id: string, set: Partial<Comment>): Promise<Comment | null>;
  findComment(id: string): Promise<Comment | null>;
  /** A deck's comments, oldest first, all statuses (the caller filters). */
  listComments(deckId: string): Promise<Comment[]>;
  /** False if this reporter already reported it. Returns the target's open-report count. */
  addReport(report: Report): Promise<{ created: boolean; open: number }>;
  openReports(limit: number): Promise<Report[]>;
  findReport(id: string): Promise<Report | null>;
  /** Closes every open report on a target. */
  resolveReports(kind: ReportKind, targetId: string, resolution: 'removed' | 'dismissed', at: number): Promise<void>;
  /**
   * A deleted account: its recaps (with everything on them), its comments
   * (replies to them stay, as top-level comments), its likes and saves (the
   * counts follow) and its reports all go.
   */
  forgetUser(uid: string): Promise<void>;
}

/** Reports that hide an item until an admin looks. */
export const HIDE_AT = 3;
export const MAX_CARDS = 300;

const newId = () => crypto.randomUUID();

/** Browsing and taking part: Pro, Super or admin (banned readers can still read). */
export function canBrowse(user: User): boolean {
  return user.tier === 'pro' || user.tier === 'super' || user.role === 'admin';
}

export function canPublish(user: User): boolean {
  return !user.banned && (user.tier === 'pro' || user.tier === 'super' || user.role === 'admin');
}

function assertActive(user: User) {
  if (user.banned) throw new ApiError('FORBIDDEN', 'आप अभी समुदाय में लिख नहीं सकते।');
}

export type PublishInput = { title: string; bookTitle: string; bookKey: string | null; blurb: string; font?: DeckFont; cards: DeckCard[] };

export async function publishDeck(store: CommunityStore, user: User, input: PublishInput, now = Date.now()): Promise<Deck> {
  if (!canPublish(user)) throw new ApiError('FORBIDDEN', 'डेक साझा करने के लिए Pro या Super प्लान चाहिए।', { reason: 'tier' });
  const deck: Deck = {
    id: newId(),
    owner: user.uid,
    title: input.title.trim(),
    bookTitle: input.bookTitle.trim(),
    bookKey: input.bookKey,
    blurb: input.blurb.trim(),
    font: input.font ?? 'montserrat',
    cards: input.cards.slice(0, MAX_CARDS),
    cardCount: Math.min(input.cards.length, MAX_CARDS),
    likes: 0,
    saves: 0,
    comments: 0,
    status: 'live',
    reports: 0,
    createdAt: now,
    updatedAt: now,
  };
  await store.insertDeck(deck);
  return deck;
}

/** The deck, if [viewer] may see it: live, or their own (not removed), or they're an admin. */
export async function visibleDeck(store: CommunityStore, id: string, viewer: User | null): Promise<Deck> {
  const deck = await store.findDeck(id);
  const admin = viewer?.role === 'admin';
  if (!deck || (deck.status !== 'live' && !admin && !(deck.owner === viewer?.uid && deck.status === 'hidden'))) {
    throw new ApiError('NOT_FOUND', 'यह डेक अब उपलब्ध नहीं है।');
  }
  return deck;
}

export async function editDeck(store: CommunityStore, user: User, id: string, input: Partial<PublishInput>, now = Date.now()): Promise<Deck> {
  const deck = await store.findDeck(id);
  if (!deck || deck.status === 'removed') throw new ApiError('NOT_FOUND', 'यह डेक अब उपलब्ध नहीं है।');
  if (deck.owner !== user.uid) throw new ApiError('FORBIDDEN', 'यह आपका डेक नहीं है।');
  assertActive(user);
  const set: Partial<Deck> = { updatedAt: now };
  if (input.title !== undefined) set.title = input.title.trim();
  if (input.blurb !== undefined) set.blurb = input.blurb.trim();
  if (input.font !== undefined) set.font = input.font;
  if (input.cards !== undefined) {
    set.cards = input.cards.slice(0, MAX_CARDS);
    set.cardCount = set.cards.length;
  }
  return (await store.updateDeck(id, set))!;
}

/** The author, or an admin, takes a deck down. */
export async function removeDeck(store: CommunityStore, user: User, id: string, now = Date.now()): Promise<Deck> {
  const deck = await store.findDeck(id);
  if (!deck || deck.status === 'removed') throw new ApiError('NOT_FOUND', 'यह डेक अब उपलब्ध नहीं है।');
  if (deck.owner !== user.uid && user.role !== 'admin') throw new ApiError('FORBIDDEN', 'यह आपका डेक नहीं है।');
  await store.resolveReports('deck', id, 'removed', now);
  return (await store.updateDeck(id, { status: 'removed', updatedAt: now }))!;
}

export type CommentResult = { comment: Comment; deck: Deck; parent: Comment | null };

export async function addComment(
  store: CommunityStore,
  user: User,
  deckId: string,
  text: string,
  parentId: string | null,
  now = Date.now(),
): Promise<CommentResult> {
  assertActive(user);
  const deck = await visibleDeck(store, deckId, user);
  let parent: Comment | null = null;
  if (parentId) {
    parent = await store.findComment(parentId);
    if (!parent || parent.deckId !== deckId || parent.status !== 'live') throw new ApiError('NOT_FOUND', 'यह टिप्पणी अब उपलब्ध नहीं है।');
    // Replies stay one level deep: a reply to a reply answers its thread.
    if (parent.parentId) parent = (await store.findComment(parent.parentId)) ?? parent;
  }
  const comment: Comment = { id: newId(), deckId, owner: user.uid, parentId: parent?.id ?? null, text: text.trim(), status: 'live', reports: 0, createdAt: now };
  await store.insertComment(comment);
  const updated = await store.updateDeck(deckId, { comments: deck.comments + 1 });
  return { comment, deck: updated ?? deck, parent };
}

export async function removeComment(store: CommunityStore, user: User, id: string, now = Date.now()): Promise<void> {
  const c = await store.findComment(id);
  if (!c || c.status === 'removed') throw new ApiError('NOT_FOUND', 'यह टिप्पणी अब उपलब्ध नहीं है।');
  const deck = await store.findDeck(c.deckId);
  // The commenter, the deck's author (it's their page) or an admin.
  if (c.owner !== user.uid && deck?.owner !== user.uid && user.role !== 'admin') throw new ApiError('FORBIDDEN', 'यह आपकी टिप्पणी नहीं है।');
  await store.updateComment(id, { status: 'removed' });
  await store.resolveReports('comment', id, 'removed', now);
  if (deck && c.status === 'live') await store.updateDeck(deck.id, { comments: Math.max(0, deck.comments - 1) });
}

/** A deck's comments as the viewer sees them: live ones, plus their own hidden ones. */
export async function visibleComments(store: CommunityStore, deckId: string, viewer: User | null): Promise<Comment[]> {
  const all = await store.listComments(deckId);
  const admin = viewer?.role === 'admin';
  return all.filter((c) => c.status === 'live' || (c.status === 'hidden' && (admin || c.owner === viewer?.uid)));
}

export async function report(store: CommunityStore, user: User, kind: ReportKind, targetId: string, reason: string, now = Date.now()): Promise<{ hidden: boolean }> {
  assertActive(user);
  const target = kind === 'deck' ? await store.findDeck(targetId) : await store.findComment(targetId);
  if (!target || target.status === 'removed') throw new ApiError('NOT_FOUND', 'यह अब उपलब्ध नहीं है।');
  if (target.owner === user.uid) throw new ApiError('BAD_REQUEST', 'अपनी चीज़ की रिपोर्ट नहीं कर सकते।');
  const r = await store.addReport({ id: newId(), kind, targetId, reporter: user.uid, reason: reason.trim(), createdAt: now, resolvedAt: null, resolution: null });
  if (!r.created) return { hidden: target.status === 'hidden' };
  const set = { reports: r.open, ...(r.open >= HIDE_AT && target.status === 'live' ? { status: 'hidden' as const } : {}) };
  if (kind === 'deck') await store.updateDeck(targetId, set);
  else await store.updateComment(targetId, set);
  return { hidden: set.status === 'hidden' || target.status === 'hidden' };
}

/** An admin's decision on everything reported about a target. */
export async function moderate(store: CommunityStore, kind: ReportKind, targetId: string, action: 'remove' | 'dismiss', now = Date.now()): Promise<{ owner: string; title: string } | null> {
  const target = kind === 'deck' ? await store.findDeck(targetId) : await store.findComment(targetId);
  if (!target) throw new ApiError('NOT_FOUND', 'यह अब उपलब्ध नहीं है।');
  if (action === 'dismiss') {
    await store.resolveReports(kind, targetId, 'dismissed', now);
    const set = { reports: 0, ...(target.status === 'hidden' ? { status: 'live' as const } : {}) };
    if (kind === 'deck') await store.updateDeck(targetId, set);
    else await store.updateComment(targetId, set);
    return null;
  }
  await store.resolveReports(kind, targetId, 'removed', now);
  if (kind === 'deck') {
    await store.updateDeck(targetId, { status: 'removed', updatedAt: now });
    return { owner: target.owner, title: (target as Deck).bookTitle };
  }
  const c = target as Comment;
  await store.updateComment(targetId, { status: 'removed' });
  if (c.status === 'live') {
    const deck = await store.findDeck(c.deckId);
    if (deck) await store.updateDeck(deck.id, { comments: Math.max(0, deck.comments - 1) });
  }
  return { owner: c.owner, title: c.text.slice(0, 60) };
}

/** In memory; tests. */
export function memoryCommunityStore(): CommunityStore & { decks: Map<string, Deck>; comments: Map<string, Comment>; reports: Map<string, Report> } {
  const decks = new Map<string, Deck>();
  const comments = new Map<string, Comment>();
  const reports = new Map<string, Report>();
  const likes = new Set<string>();
  const saves = new Set<string>();
  const score = (d: Deck) => d.likes + 2 * d.saves;
  return {
    decks,
    comments,
    reports,
    async insertDeck(d) {
      decks.set(d.id, { ...d });
    },
    async updateDeck(id, set) {
      const d = decks.get(id);
      if (!d) return null;
      const next = { ...d, ...set };
      decks.set(id, next);
      return next;
    },
    async findDeck(id) {
      return decks.get(id) ?? null;
    },
    async listDecks({ sort, q, owner, page, limit }) {
      const needle = q?.trim().toLowerCase();
      return [...decks.values()]
        .filter((d) => d.status === 'live' && (!owner || d.owner === owner))
        .filter((d) => !needle || d.bookTitle.toLowerCase().includes(needle) || d.title.toLowerCase().includes(needle))
        .sort((a, b) => (sort === 'popular' ? score(b) - score(a) || b.createdAt - a.createdAt : b.createdAt - a.createdAt))
        .slice(page * limit, page * limit + limit);
    },
    async forgetUser(uid) {
      const gone = new Set([...decks.values()].filter((d) => d.owner === uid).map((d) => d.id));
      const goneComments = new Set([...comments.values()].filter((c) => gone.has(c.deckId) || c.owner === uid).map((c) => c.id));
      for (const c of comments.values()) {
        if (c.owner !== uid || gone.has(c.deckId)) continue;
        const d = decks.get(c.deckId);
        if (d && c.status === 'live') d.comments = Math.max(0, d.comments - 1);
      }
      for (const [id, c] of comments) {
        if (goneComments.has(id)) comments.delete(id);
        else if (c.parentId !== null && goneComments.has(c.parentId)) comments.set(id, { ...c, parentId: null });
      }
      for (const [set, field] of [[likes, 'likes'], [saves, 'saves']] as const) {
        for (const key of [...set]) {
          const [deckId, who] = key.split(':') as [string, string];
          if (gone.has(deckId)) set.delete(key);
          else if (who === uid) {
            set.delete(key);
            const d = decks.get(deckId);
            if (d) d[field] = Math.max(0, d[field] - 1);
          }
        }
      }
      for (const [id, r] of reports) {
        if (r.reporter === uid || gone.has(r.targetId) || goneComments.has(r.targetId)) reports.delete(id);
      }
      for (const id of gone) decks.delete(id);
    },
    async toggleLike(deckId, uid) {
      const key = `${deckId}:${uid}`;
      const d = decks.get(deckId)!;
      const liked = !likes.has(key);
      if (liked) likes.add(key);
      else likes.delete(key);
      d.likes += liked ? 1 : -1;
      return { liked, likes: d.likes };
    },
    async likedBy(uid, ids) {
      return new Set(ids.filter((id) => likes.has(`${id}:${uid}`)));
    },
    async addSave(deckId, uid) {
      const d = decks.get(deckId)!;
      const key = `${deckId}:${uid}`;
      if (!saves.has(key)) {
        saves.add(key);
        d.saves++;
      }
      return d.saves;
    },
    async insertComment(c) {
      comments.set(c.id, { ...c });
    },
    async updateComment(id, set) {
      const c = comments.get(id);
      if (!c) return null;
      const next = { ...c, ...set };
      comments.set(id, next);
      return next;
    },
    async findComment(id) {
      return comments.get(id) ?? null;
    },
    async listComments(deckId) {
      return [...comments.values()].filter((c) => c.deckId === deckId).sort((a, b) => a.createdAt - b.createdAt);
    },
    async addReport(r) {
      const dup = [...reports.values()].some((x) => x.kind === r.kind && x.targetId === r.targetId && x.reporter === r.reporter && x.resolvedAt === null);
      if (!dup) reports.set(r.id, { ...r });
      const open = [...reports.values()].filter((x) => x.kind === r.kind && x.targetId === r.targetId && x.resolvedAt === null).length;
      return { created: !dup, open };
    },
    async openReports(limit) {
      return [...reports.values()].filter((r) => r.resolvedAt === null).sort((a, b) => a.createdAt - b.createdAt).slice(0, limit);
    },
    async findReport(id) {
      return reports.get(id) ?? null;
    },
    async resolveReports(kind, targetId, resolution, at) {
      for (const r of reports.values()) {
        if (r.kind === kind && r.targetId === targetId && r.resolvedAt === null) {
          r.resolvedAt = at;
          r.resolution = resolution;
        }
      }
    },
  };
}
