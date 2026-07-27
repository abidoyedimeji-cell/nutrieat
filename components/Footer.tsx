import Link from "next/link";

export function Footer() {
  const year = 2026;
  return (
    <footer className="border-t border-black/5 bg-brand-ink text-white/80">
      <div className="container-content grid gap-8 py-12 sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <div className="text-lg font-extrabold text-white">
            Nutri<span className="text-brand-pink">Eat</span>
          </div>
          <p className="mt-3 max-w-xs text-sm">
            Performance nutrition made practical through structured meals, realistic
            ingredients and flexible meal rotations.
          </p>
        </div>
        <div>
          <div className="text-sm font-semibold text-white">Explore</div>
          <ul className="mt-3 space-y-2 text-sm">
            <li><Link href="/#whats-inside" className="hover:text-white">What&apos;s inside</Link></li>
            <li><Link href="/early-access" className="hover:text-white">Early access</Link></li>
            <li><Link href="/blog" className="hover:text-white">Blog</Link></li>
            <li><Link href="/shop" className="hover:text-white">Shopping assistant</Link></li>
            <li><Link href="/about" className="hover:text-white">About the founder</Link></li>
          </ul>
        </div>
        <div>
          <div className="text-sm font-semibold text-white">Help</div>
          <ul className="mt-3 space-y-2 text-sm">
            <li><Link href="/faq" className="hover:text-white">FAQ</Link></li>
            <li><Link href="/privacy" className="hover:text-white">Privacy</Link></li>
            <li><Link href="/terms" className="hover:text-white">Terms</Link></li>
            <li><Link href="/refund-policy" className="hover:text-white">Refund policy</Link></li>
          </ul>
        </div>
        <div>
          <div className="text-sm font-semibold text-white">Get early access</div>
          <p className="mt-3 text-sm">
            Join before launch for exclusive pricing — 40% off PDF, 20% off hardback.
          </p>
          <Link href="/early-access" className="btn-primary mt-4">
            Join now
          </Link>
        </div>
      </div>
      <div className="border-t border-white/10">
        <div className="container-content flex flex-col items-center justify-between gap-2 py-6 text-xs text-white/50 sm:flex-row">
          <span>© {year} NutriEat. All rights reserved.</span>
          <span>UK-first · Prices in GBP (£)</span>
        </div>
      </div>
    </footer>
  );
}
