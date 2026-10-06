/**
 * GET /legal/terms and /legal/privacy: Arth's Terms of Use and Privacy
 * Policy as plain web pages, public, so the stores and the app can link to
 * them. Written from what the app and this API actually do with data; keep
 * them true when that changes.
 */
import type { FastifyPluginAsync } from 'fastify';

const CONTACT = 'ekansha13@gmail.com';
const OPERATOR = 'Akshat Jaiswal (Zethyst)';
const UPDATED = '7 October 2026';

function page(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} · Arth</title>
<style>
  :root { --paper:#f4eee3; --ink:#1b2233; --muted:#5f6573; --accent:#a3271f; --rule:#dcd2c1; }
  @media (prefers-color-scheme: dark) { :root { --paper:#151a27; --ink:#ede6d6; --muted:#9aa0ae; --accent:#e2705f; --rule:#2e3648; } }
  body { margin:0; background:var(--paper); color:var(--ink); font:17px/1.65 Georgia, "Times New Roman", serif; }
  main { max-width:44rem; margin:0 auto; padding:2.5rem 1.25rem 4rem; }
  h1 { font-size:2rem; line-height:1.2; margin:0 0 .25rem; }
  h2 { font-size:1.2rem; margin:2.2rem 0 .4rem; }
  p, li { color:var(--ink); }
  .meta { color:var(--muted); margin:0 0 2rem; }
  a { color:var(--accent); }
  ul { padding-left:1.2rem; }
  li { margin:.3rem 0; }
  footer { margin-top:3rem; padding-top:1rem; border-top:1px solid var(--rule); color:var(--muted); font-size:.95rem; }
</style>
</head>
<body><main>
${body}
<footer>Arth · <a href="/legal/terms">Terms of Use</a> · <a href="/legal/privacy">Privacy Policy</a> · <a href="mailto:${CONTACT}">${CONTACT}</a></footer>
</main></body>
</html>`;
}

const privacy = page(
  'Privacy Policy',
  `<h1>Privacy Policy</h1>
<p class="meta">Last updated ${UPDATED}</p>

<p>Arth helps Hindi readers read English books: tap a word for its meaning, a sentence for its translation, and keep what you learn as cards. This policy explains what Arth collects, why, who else handles it, and the choices you have. Arth is made by ${OPERATOR} (“we”). Questions: <a href="mailto:${CONTACT}">${CONTACT}</a>.</p>

<h2>What stays on your phone</h2>
<p>Your books never leave your phone. PDFs, EPUBs and other files you open, and photos of pages you scan, are read on the device; scanned pages are turned into text on the device, too. Your highlights, your vocabulary list and your reading settings are stored only on your phone. The offline dictionary is downloaded to your phone and looked up there.</p>

<h2>What we collect, and why</h2>
<ul>
  <li><strong>Your account</strong> (if you sign in): your name, email address and profile photo from Google, and anything you add to your profile (a photo, a short bio). Used to run your account and show your name on what you share.</li>
  <li><strong>Book covers</strong>: to show a real cover, Arth sends a book’s title, taken from its file name, to our server, which asks Open Library for a matching cover and keeps the answer. The file itself, and anything inside it, is never sent. Titles are not linked to you or your account.</li>
  <li><strong>Your cards and bookmarks</strong> (if you sign in): the cards you make (their text, your notes, the book’s title and a fingerprint of the book file, not the file) and your bookmarks, so they sync to your other phones.</li>
  <li><strong>AI answers you ask for</strong>: when you ask for a word’s meaning in a sentence, or a sentence’s translation, the word and the sentence (and, for words like “he” or “it”, the sentence before) are sent to our server and to OpenAI to produce the answer. Answers are stored so the next reader asking about the same sentence gets it instantly; stored answers are not linked to you or your account.</li>
  <li><strong>How much AI you’ve used</strong>: a count per account and per phone, to apply your plan’s allowance. The phone is identified by a code derived from its device identifier; the identifier itself isn’t sent.</li>
  <li><strong>Community</strong> (Pro and Super): recaps you publish, comments, likes, saves and reports. Recaps and comments are shown to other members with your name, photo and plan.</li>
  <li><strong>Notifications</strong>: a notification token for each phone you sign in on, and its language, to send you replies, plan changes and reminders. Review reminders are scheduled on your phone.</li>
  <li><strong>Purchases</strong>: if you buy Pro or Super, the app store handles payment; we receive which plan you have and when it renews or ends, through RevenueCat. We never see your card or UPI details.</li>
  <li><strong>How the app is used</strong>: which screens you open and a few actions (like buying a plan), with your plan, interface language, phone model and app version, through Mixpanel. This tells us which features help readers. It never includes your books, the words or sentences you look up, or your name, email or phone number; if you’re signed in, it carries your account’s ID number. We don’t use your advertising identifier for it, and Mixpanel doesn’t keep your IP address for it. You can turn it off in Arth’s settings (Share usage stats).</li>
  <li><strong>Technical logs</strong>: requests to our server (which feature, when, whether it worked) for a short time, to keep the service running and secure.</li>
</ul>

<h2>Ads</h2>
<p>If you use Arth without a paid plan, Arth shows ads from Google AdMob outside the reader. AdMob may use your phone’s advertising identifier and other information to show and measure ads. Where the law requires it, Arth asks for your consent first. You can reset or limit your advertising identifier in your phone’s settings. Pro and Super have no ads. See <a href="https://policies.google.com/technologies/ads">how Google uses information for ads</a>.</p>

<h2>Who else handles your data</h2>
<p>We use these services to run Arth, and share only what each needs:</p>
<ul>
  <li><strong>Google Firebase</strong>: sign-in and notifications.</li>
  <li><strong>MongoDB Atlas</strong>: our database (accounts, synced cards, community, stored AI answers).</li>
  <li><strong>Render</strong>: hosts our server.</li>
  <li><strong>OpenAI</strong>: produces AI answers from the words and sentences you ask about. It isn’t told who you are.</li>
  <li><strong>Open Library</strong> (Internet Archive): finds book covers from a title. It isn’t told who you are, and your phone then downloads the cover image from it.</li>
  <li><strong>Cloudinary</strong>: stores profile photos you upload.</li>
  <li><strong>Mixpanel</strong>: usage analytics (which screens and features are used). It isn’t told your name, email or phone number.</li>
  <li><strong>Google AdMob</strong>: ads, for readers without a paid plan.</li>
  <li><strong>RevenueCat, Google Play and the App Store</strong>: subscriptions.</li>
</ul>
<p>These services may process data outside India. We don’t sell your personal data.</p>

<h2>How long we keep it</h2>
<p>We keep your account, synced cards and community posts while your account exists. When you delete your account, we delete them within 30 days (backups roll over within 90 days). We keep the count of AI answers used on a phone, without any link to your account, so that a free allowance can’t be reset by creating new accounts. Stored AI answers aren’t personal data and are kept.</p>

<h2>Your choices and rights</h2>
<ul>
  <li>Use Arth without an account: reading, the offline dictionary and cards all work signed out.</li>
  <li>Delete your account in the app (You → Profile → Delete account), or see <a href="/legal/delete-account">how to delete it without the app</a>. Deleting your account doesn’t cancel a subscription; cancel that in Google Play or the App Store.</li>
  <li>See, correct or download your data: write to <a href="mailto:${CONTACT}">${CONTACT}</a>.</li>
  <li>Turn off notifications or reminders in Arth’s settings or your phone’s.</li>
  <li>Turn off usage stats in Arth’s settings.</li>
  <li>Under India’s Digital Personal Data Protection Act, 2023 you may ask to access, correct or erase your data, withdraw consent, and nominate someone to act for you. We answer within 30 days.</li>
</ul>

<h2>Children</h2>
<p>Arth is meant for readers of all ages, including students. If you are under 18, please use Arth with the consent of a parent or guardian, who can contact us about your data at any time.</p>

<h2>Security</h2>
<p>Data travels to our server encrypted (HTTPS). Access to our systems is restricted, and your phone’s identifier is hashed before it is sent. No system is perfectly secure; if something goes wrong that affects you, we’ll tell you.</p>

<h2>Changes and contact</h2>
<p>If this policy changes, we’ll update the date above and, for important changes, tell you in the app. Grievance officer and contact: ${OPERATOR}, <a href="mailto:${CONTACT}">${CONTACT}</a>.</p>`,
);

const terms = page(
  'Terms of Use',
  `<h1>Terms of Use</h1>
<p class="meta">Last updated ${UPDATED}</p>

<p>These terms are an agreement between you and ${OPERATOR} (“we”) about using Arth. By using Arth you accept them. Our <a href="/legal/privacy">Privacy Policy</a> explains how we handle your data.</p>

<h2>Arth</h2>
<p>Arth is a reading companion: an offline dictionary, AI meanings and translations, flashcards and, on paid plans, a community of readers. You bring your own books; you’re responsible for having the right to read the files you open in Arth.</p>

<h2>AI answers</h2>
<p>Meanings, translations and summaries produced by AI can be wrong or incomplete. They help you read; they aren’t professional, academic or legal advice. Please check anything important.</p>

<h2>Your account</h2>
<p>You may use Arth without an account. If you sign in, keep your Google account secure; you’re responsible for what happens under your account. One person may use several accounts, but the free AI allowance is per phone and per account, and creating accounts to get around it isn’t allowed.</p>

<h2>Plans and payment</h2>
<ul>
  <li><strong>Free</strong>: the offline dictionary, flashcards and sync, a limited number of AI answers, and ads.</li>
  <li><strong>Pro and Super</strong>: more AI answers each month (currently 500 and 5,000), no ads, scanning printed pages and the community. Allowances reset each calendar month.</li>
  <li>Subscriptions are bought through Google Play or the App Store, at the price shown in the app before you buy, and <strong>renew automatically</strong> each month or year until you cancel. You can cancel anytime in your store account; cancel at least 24 hours before renewal to avoid the next charge, and you keep your plan until the end of the period you paid for.</li>
  <li>A <strong>free trial</strong> turns into a paid subscription at the end of the trial unless you cancel before it ends. Introductory prices apply to new subscribers, once, as the store decides.</li>
  <li>Refunds are handled by Google Play or Apple under their policies.</li>
  <li>We may change plans or prices; a price change applies from your next renewal, after the store notifies you.</li>
</ul>

<h2>The community</h2>
<p>What you publish (recaps, comments) stays yours. By publishing it, you let us show it to other Arth members and let them save it to their own cards, for as long as it stays published. Don’t publish anything unlawful, hateful, harassing, sexually explicit, or that you don’t have the right to share, including long passages copied from books. Members can report content; we may remove content and suspend accounts that break these rules. You can delete what you published at any time.</p>

<h2>Acceptable use</h2>
<p>Don’t misuse Arth: no scraping or automated use of our server, no attempts to get around allowances or security, and no use that harms Arth or its readers.</p>

<h2>Ending</h2>
<p>You can stop using Arth and delete your account at any time. We may suspend or end access for serious or repeated breaches of these terms. If Arth shuts down, we’ll give reasonable notice where we can.</p>

<h2>Disclaimers and liability</h2>
<p>Arth is provided “as is”. To the extent the law allows, we aren’t liable for indirect or consequential losses, and our total liability for any claim is limited to what you paid us in the twelve months before it. Nothing in these terms limits rights you have under consumer protection law.</p>

<h2>Law</h2>
<p>These terms are governed by the laws of India, and the courts of India have jurisdiction.</p>

<h2>Changes and contact</h2>
<p>We may update these terms; we’ll change the date above and tell you in the app about important changes. Continuing to use Arth means you accept them. Contact: <a href="mailto:${CONTACT}">${CONTACT}</a>.</p>`,
);

const deleteAccount = page(
  'Delete your account',
  `<h1>Delete your Arth account</h1>
<p class="meta">Arth, by ${OPERATOR}</p>

<h2>In the app</h2>
<ol>
  <li>Open Arth and go to <strong>You</strong> (the last tab).</li>
  <li>Tap your name to open <strong>Profile</strong>.</li>
  <li>Scroll down and tap <strong>Delete account</strong>, then confirm.</li>
</ol>

<h2>Without the app</h2>
<p>Email <a href="mailto:${CONTACT}?subject=Delete%20my%20Arth%20account">${CONTACT}</a> from the email address you signed in with, asking us to delete your account. We’ll confirm and delete it within 30 days.</p>

<h2>What’s deleted</h2>
<ul>
  <li>Your account and profile (name, email, photo, bio).</li>
  <li>Your synced cards and bookmarks.</li>
  <li>Recaps you published, your comments, likes, saves and reports.</li>
  <li>Your sign-in, and the notification tokens of your phones.</li>
</ul>
<p>Replies other readers wrote to your comments stay, as their own comments. We keep the count of free AI answers used on a phone, no longer linked to you, so the free allowance can’t be reset by creating a new account. Backups roll over within 90 days. Cards and bookmarks already on your phone stay there until you delete the app.</p>

<h2>Subscriptions</h2>
<p>Deleting your account doesn’t cancel a Pro or Super subscription. Cancel it in Google Play (Payments &amp; subscriptions) or on your iPhone (Settings → your name → Subscriptions), or you’ll keep being charged.</p>`,
);

export const legalRoutes: FastifyPluginAsync = async (app) => {
  const send = (html: string) => async (_req: unknown, reply: import('fastify').FastifyReply) =>
    reply.header('cache-control', 'public, max-age=3600').type('text/html; charset=utf-8').send(html);
  app.get('/legal/privacy', send(privacy));
  app.get('/legal/terms', send(terms));
  app.get('/legal/delete-account', send(deleteAccount));
};
