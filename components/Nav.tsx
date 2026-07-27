import Link from "next/link";

const links = [
  { href: "/cookbook", label: "The Cookbook" },
  { href: "/recipes", label: "Previews" },
  { href: "/blog", label: "Blog" },
  { href: "/about", label: "About" },
  { href: "/account", label: "Account" },
];

export function Nav() {
  return (
    <header className="sticky top-0 z-40 border-b border-black/5 bg-white/85 backdrop-blur">
      <nav className="container-content flex h-16 items-center justify-between">
        <Link href="/" className="text-lg font-extrabold tracking-tight">
          Nutri<span className="text-brand-pink">Eat</span>
        </Link>
        <div className="hidden items-center gap-7 md:flex">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className="text-sm font-medium text-brand-ink/70 transition hover:text-brand-ink"
            >
              {l.label}
            </Link>
          ))}
        </div>
        <Link href="/early-access" className="btn-primary">
          Get Early Access
        </Link>
      </nav>
    </header>
  );
}
