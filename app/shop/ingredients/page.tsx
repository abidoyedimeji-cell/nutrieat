import type { Metadata } from "next";
import { getIngredientsForShopping, getRetailers } from "@/lib/shopping";
import { ShopList } from "@/components/ShopList";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Shop ingredients at UK supermarkets",
  description:
    "Search every cookbook ingredient at Tesco, Sainsbury's, Asda, Morrisons, Iceland, Ocado and Waitrose.",
};

export default async function ShopIngredientsPage() {
  const [items, retailers] = await Promise.all([getIngredientsForShopping(), getRetailers()]);
  return (
    <div className="container-content max-w-3xl py-16">
      <h1 className="text-4xl font-extrabold">Shop the ingredients</h1>
      <p className="mt-3 text-brand-ink/70">
        {items.length} ingredients — search any of them at your supermarket.
      </p>
      <div className="mt-10">
        <ShopList items={items} retailers={retailers} exportHeading="NutriEat ingredients" />
      </div>
    </div>
  );
}
