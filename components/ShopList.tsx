import { retailerSearchUrl, type Retailer, type ShoppingItem } from "@/lib/shopping";
import { ShoppingListExport } from "@/components/ShoppingListExport";

function itemLine(i: ShoppingItem): string {
  return i.quantity ? `${i.quantity}${i.unit ? ` ${i.unit}` : ""} ${i.name}` : i.name;
}

/** Level 1 + 2: a shopping list where each ingredient links out to retailer searches. */
export function ShopList({
  items,
  retailers,
  exportHeading,
}: {
  items: ShoppingItem[];
  retailers: Retailer[];
  exportHeading?: string;
}) {
  if (items.length === 0) {
    return <p className="text-sm text-brand-ink/60">No ingredients to shop yet.</p>;
  }
  return (
    <div>
      <div className="mb-6">
        <ShoppingListExport lines={items.map(itemLine)} heading={exportHeading} />
      </div>
      <ul className="divide-y divide-black/5">
        {items.map((i) => (
          <li key={i.name} className="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between">
            <span className="text-sm font-medium">{itemLine(i)}</span>
            <span className="flex flex-wrap gap-x-3 gap-y-1 text-xs">
              {retailers.map((r) => {
                const url = retailerSearchUrl(r, i.term);
                if (!url) return null;
                return (
                  <a
                    key={r.slug}
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer sponsored"
                    className="font-medium text-brand-purple hover:underline"
                  >
                    {r.name}
                  </a>
                );
              })}
            </span>
          </li>
        ))}
      </ul>
      <p className="mt-4 text-xs text-brand-ink/40">
        Links open a search on the retailer&apos;s own site. Prices and availability are shown there.
      </p>
    </div>
  );
}
