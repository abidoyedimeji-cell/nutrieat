import type { Metadata } from "next";
import "./globals.css";
import { Nav } from "@/components/Nav";
import { Footer } from "@/components/Footer";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default:
      "My Healthy Cookbook Recipe For You: Breakfast, Lunch, Smoothies and Superfoods",
    template: "%s · NutriEat",
  },
  description:
    "A digital-first performance-nutrition cookbook: structured, macro-aware meals built around practical supermarket ingredients. Join early access.",
  openGraph: {
    title: "My Healthy Cookbook Recipe For You",
    description:
      "Performance nutrition made practical — structured meals, realistic ingredients and flexible meal rotations.",
    url: siteUrl,
    siteName: "NutriEat",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="flex min-h-screen flex-col">
        <Nav />
        <main className="flex-1">{children}</main>
        <Footer />
      </body>
    </html>
  );
}
