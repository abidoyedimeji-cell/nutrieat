# The Farmers Market — 50 Stress-Test Scenarios

Step-by-step walkthroughs that exercise the marketplace model end-to-end. **No implementation
code** — each scenario drives the tables, enums and state machines fixed in
[`MARKETPLACE-ARCHITECTURE.md`](./MARKETPLACE-ARCHITECTURE.md) (source of truth for vocabulary,
state machines §4.2, money model §5, RPC plan §7, idempotency §11) against the locked commercial
rules in [`MARKETPLACE.md`](./MARKETPLACE.md). Where money moves it is shown in **integer pence**.

## Legend

- **Money rules** (locked): min order £40 (`4000`); small-order fee `199` when subtotal is
  `4000`–`5999`, `0` at `6000+`; commission **8%** (`0.080`) collection / **12%** (`0.120`)
  delivery; priority window `+299`; multi-store `+299`; **no** mixed-order fee. Merchant is paid on
  **accepted items only**: `eligible_cents = accepted_subtotal − commission_cents − Σ adjustments`.
  Rewards: pre-launch = **5% cashback** (pence); post-launch = **points** (no cash value).
- **Order enum** `market_order_status`: `draft, pending_payment, paid, awaiting_merchant, preparing,
  partially_fulfilled, out_for_delivery, delivered, completed, cancelled, partially_refunded, refunded`.
- **Sub-order enum** `merchant_order_status`: `pending, accepted, rejected, picking, packed, ready,
  collected, cancelled`.
- **Item enum** `item_fulfilment_status`: `pending, confirmed, unavailable, substituted, picking,
  picked, packed, collected, in_transit, delivered, accepted, rejected, cancelled`.
- **Task enums** `collection_task_status`: `assigned, en_route, arrived, verifying, collected,
  partial, failed, cancelled`; `delivery_task_status`: `pending, assigned, out_for_delivery,
  delivered, failed, returned, cancelled`.
- **Rejection** `rejection_status`: `submitted, under_review, merchant_disputed, approved, declined,
  resolved`. **Refund** `refund_status`: `requested, pending_review, approved, processing, completed,
  declined, failed`. **Payout** `payout_status`: `pending, eligible, processing, paid, failed,
  on_hold, reversed`. **Transfer** `transfer_status`: `pending, created, paid, failed, reversed`.
- **Actors:** Customer · Merchant staff (`owner|manager|picker`) · Driver · Platform
  (`operations|finance|support|admin`) · Stripe (webhooks) · System (scheduled jobs).
- Every privileged action appends `audit_events`; every item transition appends `item_events`;
  every evidence upload inserts an immutable `evidence_media` row (no UPDATE/DELETE).

---

## 1. Single-store collection, all items accepted

- **Initial state:** basket `priced`, one merchant (Dartford butcher), £45 collection.
- **Actors:** Customer, Merchant picker.
- **Preconditions:** subtotal ≥ 4000; address in active `collection` service_zone; merchant `active`, `collection_enabled`.
- **User actions:** places order; later collects in person.
- **Merchant actions:** accept sub-order → pick → pack → mark ready.
- **DB writes:** `market_orders` insert (`order_type=single_store`, `fulfilment_method=collection`); `merchant_sub_orders` insert (`commission_rate=0.080`); `market_order_items` insert; on accept `market_order_items.item_status: pending→confirmed`.
- **Status transitions:** order `draft→pending_payment→paid→awaiting_merchant→preparing`; sub-order `pending→accepted→picking→packed→ready→collected`; items `pending→confirmed→picking→picked→packed→collected→accepted` (customer collects; auto-confirm at window if no rejection).
- **Notifications:** customer "order placed / ready for collection"; merchant "new order".
- **Evidence:** `item_pick`, `packed_order`, `ready_for_collection`; `collection_verification` at handover.
- **Payment impact:** subtotal `4500` + small_order_fee `199` = **total `4699`** to platform.
- **Payout impact:** commission `round(4500×0.080)=360`; `eligible_cents = 4500−360 = 4140`. Small-order fee `199` = platform revenue.
- **Refund impact:** none.
- **Completion condition:** confirmation window clears with no rejection → order `completed`; settlement `eligible`.
- **Failure recovery:** re-priceable basket; order RPC unique on `basket_id`.
- **Audit trail:** `audit_events` per RPC; `item_events` for each item transition.
- **Expected result:** merchant paid `4140`, platform keeps `360 + 199`, customer charged `4699`. Correct.

## 2. Single-store delivery, all items accepted

- **Initial state:** basket `priced`, single merchant, £45, standard scheduled delivery (≥2 days out).
- **Actors:** Customer, Merchant picker, Driver.
- **Preconditions:** address inside active `delivery` zone (`ST_Covers`); slot capacity available.
- **User/Merchant/Driver actions:** customer orders; merchant accept→pick→pack→ready; driver collects then delivers.
- **DB writes:** `market_orders` (`fulfilment_method=standard`); `merchant_sub_orders` (`commission_rate=0.120`); `delivery_slots.booked_count += 1`; `collection_tasks`, `delivery_tasks` insert.
- **Status transitions:** order `…→preparing→out_for_delivery→delivered→completed`; sub-order `…→ready→collected`; items `…→collected→in_transit→delivered→accepted`; collection_task `assigned→…→collected`; delivery_task `pending→assigned→out_for_delivery→delivered`.
- **Notifications:** customer placed/collected/out-for-delivery/delivered; merchant new order + collection.
- **Evidence:** `merchant_handover`, `consolidated_load`, `delivery_proof`; auto `customer_accept` on window clear.
- **Payment impact:** subtotal `4500` + small_order_fee `199` = **`4699`**.
- **Payout impact:** commission `round(4500×0.120)=540`; `eligible = 4500−540 = 3960`.
- **Refund impact:** none.
- **Completion condition:** POD recorded, confirmation window clears → `completed`; settlement `eligible`.
- **Failure recovery:** delivery re-attempt via `delivery_task_status failed→out_for_delivery`.
- **Audit trail:** `audit_events` + `item_events` throughout; `delivery_proof` evidence.
- **Expected result:** merchant paid `3960` (12%), platform `540 + 199`, customer `4699`. Correct.

## 3. Mixed merchant + eggs + water delivery

- **Initial state:** basket has butcher meat `4000` + platform eggs `500` + platform water `1000` = subtotal `5500`, delivery.
- **Actors:** Customer, Merchant picker, Driver, Platform (inventory).
- **Preconditions:** eggs/water are `delivery_only`; platform stock available; delivery zone valid.
- **Platform actions:** reserve platform stock at order RPC (`platform_inventory.reserved_count += qty`, `inventory_movements` reason=`reserve`); on fulfil reason=`fulfil`.
- **DB writes:** `market_orders` (`order_type=mixed`); TWO sub-orders — merchant sub-order (`commission_rate=0.120`) + **platform sub-order** (`merchant_id=null`); items split across both.
- **Status transitions:** both sub-orders `pending→accepted→…→collected` (platform sub-order fulfilled from own stock); order `…→delivered→completed`.
- **Notifications:** customer + merchant; platform inventory low-stock if crossing reorder level.
- **Evidence:** merchant `packed_order`; platform `packed_order`; `delivery_proof`.
- **Payment impact:** subtotal `5500`, small_order_fee `199` (still < `6000`), **no mixed fee**, total **`5699`**.
- **Payout impact:** merchant commission `round(4000×0.120)=480`, `eligible = 4000−480 = 3520`. Eggs/water are platform-owned (own margin, no merchant transfer).
- **Refund impact:** none.
- **Completion condition:** all sub-orders delivered + window clears.
- **Failure recovery:** platform stock shortfall handled per scenarios 28–29.
- **Audit trail:** `inventory_movements` ledger + `audit_events` + `item_events`.
- **Expected result:** no mixed-order fee; merchant paid on its meat only (`3520`), platform keeps eggs/water margin + `480 + 199`. Correct.

## 4. Multi-store order

- **Initial state:** two butchers, Merchant A meat `3000`, Merchant B meat `3000`, subtotal `6000`, delivery.
- **Actors:** Customer, Merchant A + B pickers, Driver.
- **Preconditions:** both merchants in delivery zone; `merchant_count=2`.
- **DB writes:** `market_orders` (`order_type=multi_store`, `merchant_count=2`); TWO `merchant_sub_orders`, one per merchant, each `commission_rate=0.120` snapshot.
- **Status transitions:** each sub-order independently `pending→accepted→…→ready→collected`; driver two `collection_tasks`, one `delivery_task`; order `…→out_for_delivery→delivered→completed`.
- **Notifications:** both merchants; customer consolidated.
- **Evidence:** per-merchant `packed_order`/`merchant_handover`; single `consolidated_load` + `delivery_proof`.
- **Payment impact:** subtotal `6000` → small_order_fee `0`; multistore_fee `299`; total **`6299`**.
- **Payout impact:** per merchant commission `round(3000×0.120)=360`; each `eligible = 3000−360 = 2640`; **two separate transfers**, one charge. Multistore fee `299` = platform revenue.
- **Refund impact:** none.
- **Completion condition:** both sub-orders collected + delivered + window clear.
- **Failure recovery:** one merchant rejecting does not block the other (see scenario 6 semantics → `partially_fulfilled`).
- **Audit trail:** `audit_events` + `item_events`; two `merchant_settlements`.
- **Expected result:** each merchant paid `2640`, platform keeps `720 commission + 299 multistore`, customer `6299`. Correct.

## 5. Multi-store order with priority window

- **Initial state:** as scenario 4 but priority delivery window selected (`fulfilment_method=priority`).
- **Actors:** Customer, Merchant A + B, Driver.
- **Preconditions:** a priority `delivery_slots` row (`is_priority=true`) with capacity.
- **DB writes:** `market_orders` (`priority_fee_cents=299`, `multistore_fee_cents=299`); `delivery_slots.booked_count += 1` on the priority slot.
- **Status transitions:** identical to scenario 4; order rides the priority slot.
- **Notifications:** customer window-confirmed; merchants new order.
- **Evidence:** as scenario 4.
- **Payment impact:** subtotal `6000`, small_order_fee `0`, priority `299`, multistore `299`, total **`6598`**.
- **Payout impact:** commission is still **delivery 12%** per merchant (priority is a customer-side add-on, not commission): each `eligible = 3000−360 = 2640`.
- **Refund impact:** none.
- **Completion condition:** delivered inside the booked priority window + window clears.
- **Failure recovery:** missed priority window is an SLA/support matter, not a payout change; refund of `priority_fee` handled as order-level `refunds` if failed.
- **Audit trail:** `audit_events`; slot booking recorded.
- **Expected result:** priority `299` and multistore `299` are platform revenue; commission unchanged; customer `6598`. Correct.

## 6. Merchant rejects entire order before picking

- **Initial state:** single-store delivery, subtotal `4500`, sub-order `pending`.
- **Actors:** Merchant owner, Platform, Customer.
- **Preconditions:** sub-order not yet `picking` (`pending→rejected` allowed; `ready→rejected` FORBIDDEN).
- **Merchant actions:** reject whole sub-order with reason.
- **DB writes:** `merchant_sub_orders.status: pending→rejected`, `rejected_at` set, `accepted_subtotal_cents=0`; all `market_order_items.item_status → cancelled`; `refunds` insert (order-level, full).
- **Status transitions:** sub-order `pending→rejected`; single-store → order `paid/awaiting_merchant→cancelled`; items `pending→cancelled`.
- **Notifications:** customer "order cannot be fulfilled — full refund"; ops alerted.
- **Evidence:** none required (pre-pick); rejection reason on sub-order.
- **Payment impact:** customer charged `4699` at checkout.
- **Payout impact:** `accepted_subtotal=0` → commission `0`, `eligible_cents=0`. Merchant paid nothing.
- **Refund impact:** full refund `4699` (subtotal + small_order_fee returned since order fails wholesale); `refund_status: requested→…→completed`.
- **Completion condition:** refund `completed`, order `cancelled`.
- **Failure recovery:** refund idempotent via `idempotency_key`; retry safe.
- **Audit trail:** `audit_events` (merchant reject), refund ledger.
- **Expected result:** merchant `0`, customer fully refunded `4699`, order `cancelled`. Correct.

## 7. Merchant marks one item unavailable

- **Initial state:** sub-order `accepted`, 3 items; item B (`1500`) out of stock.
- **Actors:** Merchant picker, Customer, Platform.
- **Preconditions:** sub-order `accepted`; evidence required for unavailable.
- **Merchant actions:** mark item B `unavailable`; propose substitute or leave as missing line.
- **DB writes:** `market_order_items.item_status: confirmed→unavailable` for B; `item_rejections`/refund line queued for B; `merchant_sub_orders.accepted_subtotal_cents` recomputed (excludes B).
- **Status transitions:** item B `confirmed→unavailable`; other items proceed `→picking→…`; sub-order continues to `ready`.
- **Notifications:** customer "item unavailable — refunded"; merchant confirmation.
- **Evidence:** `unavailable` (`evidence_type=unavailable`).
- **Payment impact:** original total unchanged at checkout.
- **Payout impact:** if subtotal was `4500` (A+C = `3000`, B = `1500`): `accepted_subtotal=3000`, commission `round(3000×0.120)=360`, `eligible=3000−360=2640`. B contributes **£0**.
- **Refund impact:** refund item B `line_total 1500`; `refunds` insert (`item_id=B`), `market_order_items.refunded_cents=1500`.
- **Completion condition:** rest delivered + B refunded → order `partially_refunded` or `completed` with the refund line settled.
- **Failure recovery:** substitution path (scenarios 8/9) if merchant proposes instead of refunding.
- **Audit trail:** `item_events` (B unavailable), `audit_events`, refund ledger.
- **Expected result:** B refunded `1500`, merchant paid on A+C only (`2640`). Correct.

## 8. Customer approves substitution

- **Initial state:** merchant proposed substitute for item B (out of stock), `substitution_of_item_id` linked.
- **Actors:** Merchant picker, Customer.
- **Preconditions:** substitute proposed with evidence; customer window open.
- **Merchant actions:** create substitute item (`item_status=substituted`) referencing original.
- **User actions:** approve substitution.
- **DB writes:** substitute `market_order_items` insert with `substitution_of_item_id=B`; on approval `item_status: substituted→picking`; original B → `unavailable`/`cancelled`; price snapshot on the substitute line.
- **Status transitions:** substitute item `substituted→picking→…→delivered→accepted`; original `confirmed→substituted`(proposal)→`cancelled`.
- **Notifications:** customer "substitute approved"; merchant proceed.
- **Evidence:** `substitution` (`evidence_type=substitution`) — required (substitution without evidence FORBIDDEN).
- **Payment impact:** if substitute priced equal, no delta; if different, delta reconciled (top-up disallowed pre-launch → cap at original price, remainder refunded).
- **Payout impact:** substitute counts toward `accepted_subtotal` at its snapshot price; commission on accepted gross.
- **Refund impact:** only any price difference; else none.
- **Completion condition:** substitute delivered + accepted.
- **Failure recovery:** if customer does not respond before pick cutoff → treat as unavailable + refund.
- **Audit trail:** `item_events` (substituted, approved), `evidence_media` substitution row.
- **Expected result:** substitute fulfilled and paid; original excluded. Correct.

## 9. Customer rejects substitution

- **Initial state:** substitute proposed for item B; customer declines.
- **Actors:** Merchant, Customer, Platform.
- **Preconditions:** substitute in `substituted` (proposed) state, not yet picked.
- **User actions:** reject substitution.
- **DB writes:** substitute item `substituted→cancelled`; original B `confirmed→unavailable`; `refunds` insert for B line.
- **Status transitions:** substitute `substituted→cancelled`; item B treated as unavailable → refund line.
- **Notifications:** customer "no substitute — refunded"; merchant informed.
- **Evidence:** `substitution` (proposal) + `unavailable`.
- **Payment impact:** unchanged at checkout.
- **Payout impact:** B (and its substitute) contribute **£0**; commission on remaining accepted items only.
- **Refund impact:** refund B `line_total`; `refunded_cents` set.
- **Completion condition:** rest delivered; B refunded → `partially_refunded`.
- **Failure recovery:** refund idempotent.
- **Audit trail:** `item_events`, refund ledger, `audit_events`.
- **Expected result:** substitute voided, B refunded, merchant unpaid on B. Correct.

## 10. Merchant uploads wrong evidence

- **Initial state:** sub-order `picking`; merchant uploads a `packed_order` photo that is actually the wrong order.
- **Actors:** Merchant picker, Platform/Driver.
- **Preconditions:** evidence context not `locked_at`.
- **Merchant actions:** upload correction — a **new** evidence row.
- **DB writes:** original `evidence_media` row stays (immutable); new row inserted; original `superseded_by` = new row id. No UPDATE/DELETE.
- **Status transitions:** none forced; sub-order stays `picking/packed` pending valid evidence.
- **Notifications:** none unless driver/ops flags mismatch at handover.
- **Evidence:** corrected `packed_order` inserted; chain preserved via `superseded_by`.
- **Payment impact:** none.
- **Payout impact:** none (evidence quality gate only).
- **Refund impact:** none.
- **Completion condition:** valid `packed_order` present → sub-order may go `ready`.
- **Failure recovery:** if dispute later opens, `locked_at` freezes chain; both versions retained for audit.
- **Audit trail:** `audit_events` (evidence superseded), immutable `evidence_media` history.
- **Expected result:** wrong evidence never overwritten; corrected version supersedes it. Correct.

## 11. Driver finds missing item at collection

- **Initial state:** sub-order `ready`; driver arrives; one item physically absent from the handover.
- **Actors:** Merchant, Driver, Platform.
- **Preconditions:** `collection_task` in `arrived/verifying`.
- **Driver actions:** verify against manifest; flag missing item; collect the rest.
- **DB writes:** `collection_tasks.status: verifying→partial`; missing `market_order_items.item_status → unavailable` (or flagged for rejection); `accepted_subtotal_cents` recomputed.
- **Status transitions:** collection_task `arrived→verifying→partial`; sub-order stays `collected` for the collected items; missing item excluded.
- **Notifications:** customer "item missing"; merchant notified for dispute; ops.
- **Evidence:** `missing_item` (`evidence_type=missing_item`) by driver.
- **Payment impact:** unchanged at checkout.
- **Payout impact:** missing item → **£0** to merchant; commission on remaining accepted gross.
- **Refund impact:** refund the missing line; `refunds` insert.
- **Completion condition:** partial load delivered; missing item refunded.
- **Failure recovery:** merchant may dispute (scenario 18); driver evidence is the record.
- **Audit trail:** `item_events`, `collection_tasks` partial, `missing_item` evidence.
- **Expected result:** driver-verified missing item refunded, merchant not paid for it. Correct.

## 12. Driver rejects damaged item before collection

- **Initial state:** sub-order `ready`; one item visibly damaged/spoiled at handover.
- **Actors:** Merchant, Driver.
- **Preconditions:** `collection_task` `verifying`.
- **Driver actions:** refuse the damaged item; collect remainder.
- **DB writes:** damaged item `item_status → rejected` (driver-stage) with `item_rejections` insert (`reason=damaged`, actor driver); `accepted_subtotal_cents` recomputed.
- **Status transitions:** collection_task `verifying→partial`; item `packed/collected→rejected`.
- **Notifications:** customer "item not collected (damaged) — refunded"; merchant dispute channel.
- **Evidence:** `damaged_item` (`evidence_type=damaged_item`).
- **Payment impact:** unchanged.
- **Payout impact:** damaged item **£0**; commission on accepted gross only.
- **Refund impact:** refund damaged line; `refunds` insert.
- **Completion condition:** remainder delivered; damaged line refunded.
- **Failure recovery:** merchant dispute → `rejection_status: submitted→under_review→merchant_disputed`.
- **Audit trail:** `item_rejections`, `item_events`, `damaged_item` evidence.
- **Expected result:** damaged item never leaves store, refunded, merchant unpaid. Correct.

## 13. Driver collects partial order

- **Initial state:** multi-item sub-order; some items collected, some missing/damaged (combines 11+12).
- **Actors:** Merchant, Driver.
- **Preconditions:** `collection_task` `verifying`.
- **Driver actions:** collect available items; flag the rest.
- **DB writes:** collected items `→collected`; flagged items `→unavailable/rejected`; `collection_tasks.status→partial`; `accepted_subtotal_cents` recomputed to collected-and-good subset.
- **Status transitions:** sub-order `ready→collected` (for the good subset); collection_task `→partial`.
- **Notifications:** customer itemised; merchant; ops.
- **Evidence:** `merchant_handover` + `missing_item`/`damaged_item` as applicable.
- **Payment impact:** unchanged at checkout.
- **Payout impact:** merchant paid on collected-good items only; commission on that gross.
- **Refund impact:** refund each excluded line; `refunds` inserts, `refunded_cents` set.
- **Completion condition:** collected subset delivered; excluded lines refunded → `partially_refunded`.
- **Failure recovery:** re-collection task can be raised for a later run if merchant restocks (new `collection_task`).
- **Audit trail:** `item_events` per line, `collection_tasks` partial.
- **Expected result:** merchant paid only for what left the store in good condition. Correct.

## 14. Customer rejects one delivered item

- **Initial state:** order `delivered`; confirmation window open; item C (`1200`) unsatisfactory.
- **Actors:** Customer, Platform, Merchant.
- **Preconditions:** item `delivered`; window open (`delivered→rejected` allowed; `accepted→rejected` FORBIDDEN once final).
- **User actions:** reject item C with reason + photo.
- **DB writes:** `market_order_items.item_status: delivered→rejected`; `item_rejections` insert (`reason=poor_quality`, `status=submitted`); refund `requested`.
- **Status transitions:** item C `delivered→rejected`; rejection `submitted→under_review`; other items `delivered→accepted`.
- **Notifications:** customer ack; ops review queue; merchant dispute option.
- **Evidence:** `customer_reject` (`evidence_type=customer_reject`).
- **Payment impact:** unchanged at checkout.
- **Payout impact:** C put `on_hold` in settlement pending review; if approved, C contributes **£0**.
- **Refund impact:** on approval refund `1200` (`refunds`, `refund_status: requested→pending_review→approved→processing→completed`); order `delivered→partially_refunded`.
- **Completion condition:** rejection `resolved`, refund `completed`.
- **Failure recovery:** merchant dispute path (scenario 18); refund idempotent.
- **Audit trail:** `item_rejections`, `item_events`, `audit_events`.
- **Expected result:** one item refunded `1200`, rest paid, order `partially_refunded`. Correct.

## 15. Customer rejects several items

- **Initial state:** order `delivered`; customer rejects items B (`1000`) and C (`1500`) of a `4500` order.
- **Actors:** Customer, Platform, Merchant.
- **Preconditions:** items `delivered`, window open.
- **User actions:** reject B and C separately (each own reason/evidence).
- **DB writes:** two `item_rejections`; both items `delivered→rejected`; two refund lines.
- **Status transitions:** rejections `submitted→under_review`; item A stays `accepted`.
- **Notifications:** customer; ops (two review items); merchant.
- **Evidence:** two `customer_reject` rows.
- **Payment impact:** unchanged.
- **Payout impact:** accepted = A only (`2000`); commission `round(2000×0.120)=240`; `eligible=2000−240=1760`. B+C **£0** if approved.
- **Refund impact:** refunds total `2500` (`1000+1500`) via two `refunds` rows; order `→partially_refunded`.
- **Completion condition:** both rejections resolved, both refunds completed.
- **Failure recovery:** per-item; one may be declined while other approved.
- **Audit trail:** two `item_rejections`, `item_events`, settlement recompute.
- **Expected result:** merchant paid `1760` on A only, customer refunded `2500`. Correct.

## 16. Customer claims missing item

- **Initial state:** order `delivered` per driver POD, but customer says item D (`800`) not in the bag.
- **Actors:** Customer, Driver, Platform.
- **Preconditions:** item `delivered`; window open.
- **User actions:** report missing item.
- **DB writes:** `item_rejections` insert (`reason=missing`, `status=submitted`); item D flagged; ops reconcile against driver evidence.
- **Status transitions:** rejection `submitted→under_review`; item D `delivered→rejected` if approved.
- **Notifications:** customer; ops; driver may be queried.
- **Evidence:** customer `missing_item`/`customer_reject` vs driver `delivery_proof`/`consolidated_load` — conflicting evidence resolved by ops.
- **Payment impact:** unchanged.
- **Payout impact:** if approved D contributes **£0**; if declined merchant keeps D gross.
- **Refund impact:** conditional refund `800` on approval; declined = no refund.
- **Completion condition:** ops decision; rejection `resolved`.
- **Failure recovery:** driver `delivery_proof` is the tie-breaker; support case may open.
- **Audit trail:** `item_rejections`, both evidence chains, ops `audit_events`.
- **Expected result:** claim adjudicated against driver POD; refund only if substantiated. Correct.

## 17. Customer uploads conflicting evidence

- **Initial state:** customer rejection with a photo that does not match the order/item.
- **Actors:** Customer, Platform (ops).
- **Preconditions:** rejection `under_review`.
- **User actions:** submitted rejection + evidence.
- **Platform actions:** ops compares to merchant `packed_order` + driver `delivery_proof`; `sha256`/metadata cross-check.
- **DB writes:** no destructive change; `item_rejections.status` set by ops; `merchant_response`/review notes.
- **Status transitions:** rejection `under_review→declined` (evidence insufficient) or `→approved` if corroborated.
- **Notifications:** customer decision; support case if disputed.
- **Evidence:** all `evidence_media` rows immutable; `locked_at` set once dispute opens.
- **Payment impact:** none until decision.
- **Payout impact:** settlement stays `on_hold` during review; releases on decision.
- **Refund impact:** refund only if `approved`; declined = £0.
- **Completion condition:** ops resolves; rejection `resolved`.
- **Failure recovery:** support_case escalation; evidence chain preserved.
- **Audit trail:** ops `audit_events`, locked evidence, review notes.
- **Expected result:** conflicting evidence cannot silently pay out; ops adjudicates on locked chain. Correct.

## 18. Merchant disputes customer rejection

- **Initial state:** rejection `under_review`; merchant contests it.
- **Actors:** Merchant, Platform (ops), Customer.
- **Preconditions:** rejection not yet `approved`/`declined`.
- **Merchant actions:** submit `merchant_response` + counter-evidence.
- **DB writes:** `item_rejections.status: under_review→merchant_disputed`, `merchant_response` set; merchant counter `evidence_media` insert.
- **Status transitions:** rejection `under_review→merchant_disputed→approved | declined`.
- **Notifications:** ops review; customer informed dispute opened.
- **Evidence:** merchant `packed_order`/`merchant_handover` vs customer `customer_reject`; `locked_at` set.
- **Payment impact:** none during dispute.
- **Payout impact:** settlement `on_hold` until dispute resolves; then `eligible` recomputed.
- **Refund impact:** approved → refund proceeds; declined → no refund, merchant keeps gross.
- **Completion condition:** ops final decision; rejection `resolved`.
- **Failure recovery:** finance can adjust settlement post-decision via `settlement_adjustments`.
- **Audit trail:** full evidence chain, `audit_events`, dispute trail.
- **Expected result:** merchant gets a fair hearing; payout reflects final ruling. Correct.

## 19. Platform approves full item refund

- **Initial state:** rejection `under_review`; ops approve full line refund for item C (`1200`).
- **Actors:** Platform (ops/finance), Stripe.
- **Preconditions:** rejection valid; refund RPC idempotency key.
- **Platform actions:** approve refund; execute Stripe refund.
- **DB writes:** `refunds` `status: requested→pending_review→approved→processing→completed`; `market_order_items.refunded_cents=1200`; `item_rejections.status→approved→resolved`; `settlement_adjustments` insert (`amount_cents=−1200`... but note commission already excluded, see below).
- **Status transitions:** refund state machine to `completed`; order `delivered→partially_refunded`.
- **Notifications:** customer refund confirmed; merchant settlement adjusted.
- **Evidence:** approval linked to `customer_reject` chain.
- **Payment impact:** Stripe refund `1200` to customer.
- **Payout impact:** C already excluded from `accepted_subtotal`, so merchant simply not paid the `1200`; commission recomputed on accepted gross only. No double deduction.
- **Refund impact:** `1200` refunded; `refund.stripe_refund_id` + `idempotency_key` unique.
- **Completion condition:** Stripe `charge.refunded` webhook confirms → `completed`.
- **Failure recovery:** `processing→failed→processing` retry same idempotency key.
- **Audit trail:** `refunds`, `settlement_adjustments`, `audit_events`.
- **Expected result:** customer refunded `1200`, merchant unpaid for C, no double-charge to merchant. Correct.

## 20. Platform approves partial refund

- **Initial state:** item delivered but partially unsatisfactory (e.g. 1 of 2 units bad); line `1600` (`2×800`), refund `800`.
- **Actors:** Platform (ops/finance), Customer.
- **Preconditions:** `qty_rejected < qty`; partial refund supported.
- **Platform actions:** approve partial refund for `accepted_qty=1`, `rejected_qty=1`.
- **DB writes:** `market_order_items.accepted_qty=1`, `rejected_qty=1`, `refunded_cents=800`; `refunds.amount_cents=800`; `item_rejections.qty_rejected=1`.
- **Status transitions:** item stays partly `accepted`; refund `→completed`; order `→partially_refunded`.
- **Notifications:** customer partial refund; merchant partial adjustment.
- **Evidence:** `customer_reject`.
- **Payment impact:** Stripe refund `800`.
- **Payout impact:** `accepted_subtotal` includes 1 accepted unit (`800`); commission on that; the refunded unit contributes £0.
- **Refund impact:** `800`.
- **Completion condition:** refund completed, rejection resolved.
- **Failure recovery:** idempotent.
- **Audit trail:** `refunds`, `item_events` (partial), `settlement_adjustments` if needed.
- **Expected result:** exactly one unit refunded (`800`), merchant paid for the good unit. Correct.

## 21. Platform declines refund

- **Initial state:** rejection `under_review` / `merchant_disputed`; ops decline.
- **Actors:** Platform (ops), Customer, Merchant.
- **Preconditions:** insufficient/contradicted evidence.
- **Platform actions:** decline.
- **DB writes:** `item_rejections.status→declined→resolved`; `refunds.status: pending_review→declined`; no `refunded_cents` change; item stays `accepted`.
- **Status transitions:** rejection `→declined→resolved`; refund `declined`; item remains `accepted`.
- **Notifications:** customer decline + reason; merchant informed.
- **Evidence:** locked chain retained.
- **Payment impact:** no refund.
- **Payout impact:** item stays in `accepted_subtotal`; merchant paid in full for it; settlement `on_hold→eligible`.
- **Refund impact:** none.
- **Completion condition:** rejection `resolved`; order proceeds to `completed`.
- **Failure recovery:** customer may open a `support_case` to escalate.
- **Audit trail:** decline reason in `audit_events`, locked evidence.
- **Expected result:** no refund; merchant retains full payout for the item. Correct.

## 22. Customer cancels before acceptance

- **Initial state:** order `paid`/`awaiting_merchant`; no merchant acceptance yet; within `cancellation_deadline`.
- **Actors:** Customer, Platform, Stripe.
- **Preconditions:** no sub-order `accepted`.
- **User actions:** cancel order.
- **DB writes:** `market_orders.status→cancelled`, `cancelled_at`, `cancel_reason`; all items `→cancelled`; `refunds` full; `platform_inventory` release (`reserved_count -=`, `inventory_movements` reason=`release`); `delivery_slots.booked_count -= 1`.
- **Status transitions:** order `paid→cancelled`; sub-orders `pending→cancelled`.
- **Notifications:** customer cancellation + refund; merchant order withdrawn.
- **Evidence:** none.
- **Payment impact:** customer charged `total_cents` at checkout.
- **Payout impact:** none — no accepted items, `eligible=0`.
- **Refund impact:** full refund of `total_cents` (fees included, pre-acceptance).
- **Completion condition:** refund `completed`, order `cancelled`.
- **Failure recovery:** refund idempotent; slot/stock release idempotent.
- **Audit trail:** `audit_events`, `inventory_movements`, refund ledger.
- **Expected result:** full refund, stock + slot released, merchant unaffected. Correct.

## 23. Customer cancels after merchant acceptance

- **Initial state:** sub-order `accepted` (maybe `picking`); customer requests cancel.
- **Actors:** Customer, Merchant, Platform.
- **Preconditions:** `accepted→cancelled` allowed before picking completes; policy may restrict once picking begins.
- **User actions:** request cancel.
- **DB writes:** if permitted, `merchant_sub_orders.status: accepted→cancelled`, items `→cancelled`; `refunds`; else request routed to `support_cases`.
- **Status transitions:** sub-order `accepted→cancelled`; order `→cancelled` (single-store) or `partially_fulfilled` (multi-store, one merchant cancelled).
- **Notifications:** customer; merchant (stop work).
- **Evidence:** none unless picking already produced evidence.
- **Payment impact:** charged at checkout.
- **Payout impact:** cancelled sub-order `eligible=0`. If merchant already picked/incurred cost, ops may grant a goodwill `settlement_adjustment` (policy).
- **Refund impact:** refund of that sub-order's lines (+ proportional fees per policy).
- **Completion condition:** refund completed; order/sub-order `cancelled`.
- **Failure recovery:** if merchant already `ready`, cancel is refused → becomes a rejection/refund flow instead.
- **Audit trail:** `audit_events`, `item_events`, refund ledger.
- **Expected result:** cancellation honoured pre-picking with full refund; merchant work-cost handled by policy adjustment. Correct.

## 24. Customer cancels during picking

- **Initial state:** sub-order `picking`; some items `picked`.
- **Actors:** Customer, Merchant, Platform.
- **Preconditions:** picking in progress; state machine forbids silent reversal of picked items.
- **User actions:** request cancel.
- **Platform actions:** route to ops/support — not an automatic self-serve cancel once picking started.
- **DB writes:** `support_cases` insert; if approved, `merchant_sub_orders→cancelled`, items `picking/picked→cancelled` (allowed pre-collected); `refunds`; possible `settlement_adjustment` for merchant cost.
- **Status transitions:** items `picking→cancelled` (pre-collected cancel allowed); sub-order `picking→cancelled` via ops.
- **Notifications:** customer pending review; merchant halt.
- **Evidence:** any `item_pick` already captured is retained.
- **Payment impact:** charged at checkout.
- **Payout impact:** cancelled → `eligible=0`; goodwill adjustment optional.
- **Refund impact:** refund per policy (may exclude non-recoverable perishable cost).
- **Completion condition:** ops decision; refund settled.
- **Failure recovery:** if items already collected, becomes delivery/rejection flow, not cancel.
- **Audit trail:** `support_cases`, `audit_events`, `item_events`.
- **Expected result:** mid-pick cancel gated through ops; refund reflects perishable policy. Correct.

## 25. Failed delivery

- **Initial state:** order `out_for_delivery`; driver cannot complete (address, access).
- **Actors:** Driver, Customer, Platform.
- **Preconditions:** `delivery_task` `out_for_delivery`.
- **Driver actions:** mark failed with reason + evidence.
- **DB writes:** `delivery_tasks.status: out_for_delivery→failed`, `attempts += 1`; items stay `in_transit`.
- **Status transitions:** delivery_task `failed→out_for_delivery` (re-attempt) or `failed→returned`; order stays `out_for_delivery` until re-attempt or `returned` handling.
- **Notifications:** customer failed-attempt + reschedule; ops.
- **Evidence:** `delivery_proof` of attempt (photo/location).
- **Payment impact:** charged at checkout.
- **Payout impact:** perishable loss on `returned` → who bears cost is a policy adjustment (`settlement_adjustments`); merchant payout may be held.
- **Refund impact:** depends on cause — customer-fault (unavailable) vs platform-fault; refund only if policy grants.
- **Completion condition:** successful re-attempt → `delivered`; or `returned` + policy resolution.
- **Failure recovery:** `failed→out_for_delivery` re-attempt increments `attempts`.
- **Audit trail:** `delivery_tasks`, attempt evidence, `audit_events`.
- **Expected result:** failed delivery re-attempted or returned; cost allocated by policy, not silently. Correct.

## 26. Customer unavailable

- **Initial state:** `out_for_delivery`; customer not present, perishable goods.
- **Actors:** Driver, Customer.
- **Preconditions:** delivery window active.
- **Driver actions:** attempt, wait, then mark failed (customer unavailable).
- **DB writes:** `delivery_tasks.status→failed`, `attempts += 1`; reason `customer_unavailable`.
- **Status transitions:** delivery_task `out_for_delivery→failed→returned` (perishables cannot re-hold across days) or single re-attempt within window.
- **Notifications:** customer missed-delivery; ops.
- **Evidence:** `delivery_proof` (attempt).
- **Payment impact:** charged.
- **Payout impact:** merchant delivered goods in good faith → payout generally stands; loss allocation is policy (perishable spoilage).
- **Refund impact:** typically **no** refund (customer-fault) per cancellation/consumer policy.
- **Completion condition:** `returned`; support closes.
- **Failure recovery:** limited re-attempt inside the 04:00–11:00 window; else returned.
- **Audit trail:** `delivery_tasks`, evidence, `audit_events`.
- **Expected result:** customer-fault non-delivery → merchant still paid, refund per policy only. Correct.

## 27. Address outside delivery zone

- **Initial state:** basket pricing / order RPC; address is discoverable but outside delivery polygon.
- **Actors:** Customer, Platform.
- **Preconditions:** **discovery radius ≠ delivery eligibility** — `ST_DWithin` (5 mi) may pass while `ST_Covers(delivery_zone.area, address)` fails.
- **User actions:** attempt delivery order.
- **Platform actions:** order RPC rejects at precondition (must be inside active `delivery` `service_zones`).
- **DB writes:** none committed; basket stays `priced`; no `market_orders` row.
- **Status transitions:** none (order never created).
- **Notifications:** customer "delivery unavailable to this address — collection may be available."
- **Evidence:** none.
- **Payment impact:** none (blocked pre-payment).
- **Payout impact:** none.
- **Refund impact:** none.
- **Completion condition:** customer switches to collection (if in `collection` zone) or abandons.
- **Failure recovery:** offer `location_waitlist` vote for the town; suggest collection.
- **Audit trail:** blocked attempt logged in `audit_events`.
- **Expected result:** browsing allowed, delivery correctly refused outside the delivery zone. Correct.

## 28. Eggs out of stock

- **Initial state:** basket includes platform eggs; at order RPC `platform_inventory.available_count < qty`.
- **Actors:** Customer, Platform.
- **Preconditions:** eggs are platform-owned, `delivery_only`; reserve step in order RPC.
- **Platform actions:** reserve fails → block or drop the egg line.
- **DB writes:** no `reserve` movement committed; if partial-allowed, egg line removed from basket; else RPC aborts (unique on `basket_id` keeps it re-runnable).
- **Status transitions:** none for eggs (never reserved); rest of order proceeds if re-priced.
- **Notifications:** customer "eggs unavailable"; ops low-stock/reorder alert.
- **Evidence:** none.
- **Payment impact:** eggs excluded from `total_cents`; re-price before charge.
- **Payout impact:** none (platform-owned).
- **Refund impact:** none if caught pre-charge; if discovered post-charge → refund egg line + `inventory_movements` reason=`release`.
- **Completion condition:** order placed without eggs, or aborted.
- **Failure recovery:** `platform_inventory` reorder; `inventory_movements` restock later.
- **Audit trail:** `inventory_movements`, `audit_events`.
- **Expected result:** eggs never oversold; reservation is atomic against `available_count`. Correct.

## 29. Water out of stock

- **Initial state:** basket includes Hildon water (case 12×1L); stock insufficient at RPC.
- **Actors:** Customer, Platform.
- **Preconditions:** platform-owned, `delivery_only`.
- **Platform actions:** reservation against `available_count` fails.
- **DB writes:** as scenario 28 — no `reserve` movement; water line dropped or RPC aborts.
- **Status transitions:** none for water.
- **Notifications:** customer; ops reorder.
- **Evidence:** none.
- **Payment impact:** water excluded pre-charge; re-price.
- **Payout impact:** none.
- **Refund impact:** only if post-charge discovery → refund + `release` movement.
- **Completion condition:** order without water, or aborted.
- **Failure recovery:** reorder; note water may push subtotal below £40 min or £60 fee threshold — re-validate min-order and `small_order_fee`.
- **Audit trail:** `inventory_movements`, `audit_events`.
- **Expected result:** water never oversold; removing it re-triggers min-order + fee checks. Correct.

## 30. Merchant store unexpectedly closed

- **Initial state:** sub-order `ready` (or `accepted`); driver arrives, store shut.
- **Actors:** Driver, Merchant, Platform.
- **Preconditions:** `collection_task` `arrived`.
- **Driver actions:** mark task failed (store closed / no goods).
- **DB writes:** `collection_tasks.status: arrived→failed`, `failed_at`; sub-order held; items not collected.
- **Status transitions:** collection_task `arrived→failed`; sub-order stays `ready` (new task) or moves to refund path if unrecoverable.
- **Notifications:** customer delay/cancel; merchant escalation; ops.
- **Evidence:** `missing_item`/failure photo; store-closed note.
- **Payment impact:** charged at checkout.
- **Payout impact:** uncollected sub-order → `eligible=0`; merchant `quality_score` impact; possible `suspended` review.
- **Refund impact:** full refund of that sub-order's lines (+ fee proportion) if unrecoverable.
- **Completion condition:** re-collection succeeds, or refund + order `cancelled`/`partially_fulfilled`.
- **Failure recovery:** raise a fresh `collection_task` for a later run; `failed→collected` on same task FORBIDDEN.
- **Audit trail:** `collection_tasks`, `audit_events`, merchant flag.
- **Expected result:** closed store → no payout, customer refunded, merchant flagged. Correct.

## 31. Driver breakdown

- **Initial state:** `route` active; driver vehicle fails mid-run; some sub-orders collected, some not.
- **Actors:** Driver, Platform, Customer.
- **Preconditions:** `routes.status=active`; tasks in mixed states.
- **Platform actions:** reassign route/tasks to another driver.
- **DB writes:** `routes.status: active→cancelled` (or reassign); open `collection_tasks`/`delivery_tasks` reassigned (`driver_id` updated) or `→cancelled` and re-created on a new route.
- **Status transitions:** affected tasks `→cancelled`/reassigned; collected goods still `collected`, in-transit stays `in_transit`.
- **Notifications:** customers delayed; ops; new driver.
- **Evidence:** existing collection evidence retained.
- **Payment impact:** charged at checkout.
- **Payout impact:** unaffected for collected items; uncollected sub-orders pending re-collection.
- **Refund impact:** only if goods spoil/undeliverable (policy).
- **Completion condition:** reassigned run delivers; or refunds for unrecoverable orders.
- **Failure recovery:** cold-chain time limits inside 04:00–11:00 window may force refunds for delayed perishables.
- **Audit trail:** `routes`, `collection_tasks`/`delivery_tasks` reassignment, `audit_events`.
- **Expected result:** in-flight work preserved, remaining tasks reassigned, refunds only where goods lost. Correct.

## 32. Delivery route over capacity

- **Initial state:** booking a delivery slot whose `booked_count = capacity`.
- **Actors:** Customer, Platform, System.
- **Preconditions:** `delivery_slots.capacity` reached; booking increments guarded.
- **Platform actions:** order RPC checks slot capacity before commit.
- **DB writes:** if full, no `booked_count` increment, RPC aborts; else `booked_count += 1` atomically.
- **Status transitions:** order not created if slot full.
- **Notifications:** customer "slot full — choose another window."
- **Evidence:** none.
- **Payment impact:** blocked pre-charge.
- **Payout impact:** none.
- **Refund impact:** none.
- **Completion condition:** customer picks an open slot (`is_open=true`, `booked_count < capacity`).
- **Failure recovery:** ops can raise `capacity` or open new `delivery_slots`; `route` batching respects `booked_count`.
- **Audit trail:** `audit_events` blocked booking.
- **Expected result:** slot capacity never exceeded; over-capacity booking refused atomically. Correct.

## 33. Duplicate Stripe webhook

- **Initial state:** `payment_intent.succeeded` delivered twice for the same order.
- **Actors:** Stripe, Platform (webhook).
- **Preconditions:** `market_payment_events(stripe_event_id UNIQUE)`.
- **Platform actions:** webhook checks-then-inserts event id before acting.
- **DB writes:** first delivery: `market_payment_events` insert + `market_orders.status→paid` + sub-orders `→pending` + notify. Second delivery: unique violation on `stripe_event_id` → **no-op**.
- **Status transitions:** first advances order; second is skipped (idempotent).
- **Notifications:** merchants notified once only.
- **Evidence:** none.
- **Payment impact:** order marked `paid` exactly once; no double side-effects.
- **Payout impact:** none double-counted.
- **Refund impact:** none.
- **Completion condition:** exactly-once processing.
- **Failure recovery:** event recorded **after** success so a genuine failure retries safely.
- **Audit trail:** `market_payment_events`, `audit_events`.
- **Expected result:** redelivered webhook is a safe no-op. Correct.

## 34. Duplicate order submission

- **Initial state:** customer double-clicks checkout; two order-create RPCs for one basket.
- **Actors:** Customer, Platform.
- **Preconditions:** order creation **unique on `basket_id`**.
- **User actions:** submit twice.
- **DB writes:** first: `market_orders` + sub-orders + items + stock reserve + slot booking. Second: unique violation on `basket_id` → returns existing order, no new rows.
- **Status transitions:** one order created; second call no-ops to the same order.
- **Notifications:** single confirmation.
- **Evidence:** none.
- **Payment impact:** one `total_cents`; single PaymentIntent reused on retry.
- **Payout impact:** none duplicated.
- **Refund impact:** none.
- **Completion condition:** exactly one order per basket.
- **Failure recovery:** PI reused on retry (RPC plan: "reuse PI on retry").
- **Audit trail:** `audit_events` (dedup), single order row.
- **Expected result:** one basket → one order, no duplicate charge or double stock reserve. Correct.

## 35. Payment succeeds but order creation response fails

- **Initial state:** Stripe charged; the client never received the create/confirm response (network drop).
- **Actors:** Customer, Stripe, Platform.
- **Preconditions:** idempotent order creation + webhook truth.
- **Platform actions:** Stripe `payment_intent.succeeded` webhook is the source of truth and drives `→paid`, independent of the client response.
- **DB writes:** order already created (unique `basket_id`); webhook sets `→paid` via `market_payment_events`.
- **Status transitions:** order reaches `paid` from the webhook even though the client saw an error.
- **Notifications:** confirmation sent on webhook success.
- **Evidence:** none.
- **Payment impact:** single charge reconciled; no double order.
- **Payout impact:** normal.
- **Refund impact:** none (no duplicate to refund).
- **Completion condition:** order `paid`, customer sees it on refresh/order history.
- **Failure recovery:** client retry hits unique `basket_id` and returns the existing order.
- **Audit trail:** `market_payment_events`, `audit_events`.
- **Expected result:** money and order stay consistent via webhook truth despite the failed response. Correct.

## 36. Refund webhook arrives twice

- **Initial state:** `charge.refunded` delivered twice for one refund.
- **Actors:** Stripe, Platform (finance webhook).
- **Preconditions:** `market_payment_events(stripe_event_id UNIQUE)`; `refunds.stripe_refund_id UNIQUE`, `idempotency_key UNIQUE`.
- **Platform actions:** webhook checks event id then advances refund.
- **DB writes:** first: `market_payment_events` insert + `refunds.status→completed` + `settlement_adjustments`. Second: unique violation → no-op.
- **Status transitions:** refund `processing→completed` once; second delivery skipped.
- **Notifications:** customer refunded once.
- **Evidence:** none.
- **Payment impact:** exactly one refund recorded.
- **Payout impact:** one settlement adjustment, not two.
- **Refund impact:** single refund amount honoured.
- **Completion condition:** refund `completed` exactly once.
- **Failure recovery:** idempotent by event id + refund id.
- **Audit trail:** `market_payment_events`, `refunds`, `audit_events`.
- **Expected result:** duplicate refund webhook is a safe no-op; no double refund. Correct.

## 37. Merchant payout fails

- **Initial state:** settlement `eligible`; Stripe transfer fails (bank/account issue).
- **Actors:** Platform (finance), Stripe.
- **Preconditions:** `merchant_settlements.status=eligible`, `payouts_enabled`.
- **Platform actions:** release transfer; Stripe returns failure / `transfer.failed`.
- **DB writes:** `merchant_transfers.status: pending→created→failed`, `failure_reason` set; `merchant_settlements.status: processing→failed`.
- **Status transitions:** payout `processing→failed→processing` (retry same `idempotency_key`); transfer `failed→…` on retry.
- **Notifications:** finance alerted; merchant "payout delayed."
- **Evidence:** none.
- **Payment impact:** customer already paid; funds still on platform balance.
- **Payout impact:** `eligible_cents` unchanged; merchant not yet paid.
- **Refund impact:** none.
- **Completion condition:** retry succeeds → `transfer.paid` webhook → payout `paid`.
- **Failure recovery:** retry with **same** `idempotency_key` (no double transfer); if account restricted → scenario 38.
- **Audit trail:** `merchant_transfers`, `audit_events`.
- **Expected result:** failed payout retried idempotently; funds held safely until success. Correct.

## 38. Merchant Stripe Connect account restricted

- **Initial state:** `account.updated` shows `payouts_enabled=false` / requirements due.
- **Actors:** Stripe, Platform (finance), Merchant.
- **Preconditions:** Connect Express account event-driven mirror.
- **Platform actions:** consume `account.updated`; block transfers.
- **DB writes:** `connect_accounts` updated (`payouts_enabled=false`, `requirements`, `status`); `merchants.connect_status` denormalised update; affected `merchant_settlements.status: eligible→on_hold`.
- **Status transitions:** settlement `eligible→on_hold` (payout gate requires `payouts_enabled`); no transfer issued.
- **Notifications:** merchant "complete Stripe requirements"; ops.
- **Evidence:** none.
- **Payment impact:** customer unaffected; funds held on platform.
- **Payout impact:** payout gated until account restored; then `on_hold→eligible→processing→paid`.
- **Refund impact:** none.
- **Completion condition:** merchant clears KYC → `payouts_enabled=true` → settlement releases.
- **Failure recovery:** funds never leave early; held through the window.
- **Audit trail:** `market_payment_events` (account.updated), `connect_accounts`, `audit_events`.
- **Expected result:** restricted account holds payout; no transfer while `payouts_enabled=false`. Correct.

## 39. Customer uses referral code

- **Initial state:** new referred customer places first qualifying order using a `referral_codes.code`.
- **Actors:** Referred customer, Referrer, System.
- **Preconditions:** valid active code; regime by launch date (pre-launch cashback / post-launch points).
- **User actions:** apply code at order/registration.
- **DB writes:** `referrals` insert/update (`referral_code_id`, `referred_user_id`, `order_ref`, `regime`, `status=pending`, `window_clears_at`).
- **Status transitions:** referral `pending→qualified` after order completed + cancellation window clears (post-launch requires received/collected + window).
- **Notifications:** referrer "referral pending"; on qualify "reward earned."
- **Evidence:** none.
- **Payment impact:** referral does not change buyer total (reward accrues to referrer).
- **Payout impact:** none to merchant.
- **Refund/Reward impact:** on qualify, `reward_ledger` insert — **pre-launch** `kind=cashback` pence (e.g. 5% of £17.99 pre-order ≈ `90`); **post-launch** `kind=points` (no cash value). Never summed.
- **Completion condition:** referral `qualified→paid`; ledger credited.
- **Failure recovery:** qualification gated on completion + window; reversible if order later refunded (scenario 40).
- **Audit trail:** `referrals`, `reward_ledger`, `audit_events`.
- **Expected result:** referral credited only after real completion; correct regime + units. Correct.

## 40. Referral order refunded

- **Initial state:** referral `pending`/`qualified`; the qualifying order is refunded/cancelled.
- **Actors:** System, Referrer, Platform.
- **Preconditions:** `referral_status` machine allows `pending→void` and `qualified→void`.
- **Platform actions:** refund triggers referral re-evaluation.
- **DB writes:** `referrals.status → void`; if reward already credited, reverse `reward_ledger` (offsetting `delta`, new `balance_after`).
- **Status transitions:** referral `pending→void` (before qualify) or `qualified→void` (post-qualify clawback).
- **Notifications:** referrer "referral reversed."
- **Evidence:** none.
- **Payment impact:** tied to the order's own refund.
- **Payout impact:** merchant payout follows the refund (accepted-items rule).
- **Refund/Reward impact:** referral reward removed; cashback/points reversed via offsetting ledger row.
- **Completion condition:** referral `void`, ledger balanced.
- **Failure recovery:** idempotent reversal; `void→qualified` FORBIDDEN.
- **Audit trail:** `referrals`, `reward_ledger` reversal, `audit_events`.
- **Expected result:** refunded qualifying order voids the referral and claws back the reward. Correct.

## 41. Cashback awarded then order refunded (clawback)

- **Initial state:** pre-launch cashback `90` credited to referrer (`reward_ledger kind=cashback`); referred order refunded.
- **Actors:** System, Referrer, Finance.
- **Preconditions:** cashback is a tracked pence value; clawback allowed.
- **Platform actions:** on refund, reverse the cashback.
- **DB writes:** `reward_ledger` offsetting row `kind=cashback, delta=−90`, `balance_after` recomputed, `reason='referral_reversed'`, `reference_id`=order; `referrals.status→void`.
- **Status transitions:** referral `qualified→void`.
- **Notifications:** referrer "cashback reversed due to refund."
- **Evidence:** none.
- **Payment impact:** buyer's own refund handled separately.
- **Payout impact:** n/a (referrer reward, not merchant).
- **Refund/Reward impact:** cashback net effect `0`; if already partially redeemed, negative balance handled per policy (hold future accrual).
- **Completion condition:** ledger reflects reversal; referral `void`.
- **Failure recovery:** offsetting entries only — never edit historical ledger rows.
- **Audit trail:** append-only `reward_ledger` pair, `audit_events`.
- **Expected result:** cashback clawed back via offsetting ledger entry; balance corrected without mutation. Correct.

## 42. Points reward redeemed

- **Initial state:** post-launch customer redeems points for a `reward_catalogue` item with `stock` available.
- **Actors:** Customer, System.
- **Preconditions:** `reward_ledger` points balance ≥ `cost_points`; catalogue `status=active`, `stock>0`.
- **User actions:** redeem.
- **DB writes:** `reward_redemptions` insert (`status=requested→reserved`, `reward_catalogue_id`); `reward_ledger` debit `kind=points, delta=−cost_points`; `reward_catalogue.stock -= 1`.
- **Status transitions:** redemption `requested→reserved→fulfilled`.
- **Notifications:** customer redemption confirmed.
- **Evidence:** none.
- **Payment impact:** points have **no fixed cash value**; a points→discount is capped by `reward_catalogue.discount_cap_cents`.
- **Payout impact:** none.
- **Refund/Reward impact:** points debited once (idempotent redemption key); never mixed with cashback pence.
- **Completion condition:** redemption `fulfilled`; stock decremented.
- **Failure recovery:** if stock gone mid-flight → scenario 43 (`reserved→cancelled`, points returned).
- **Audit trail:** `reward_ledger`, `reward_redemptions`, `audit_events`.
- **Expected result:** points debited atomically with stock reservation; capped discount honoured. Correct.

## 43. Reward stock becomes unavailable

- **Initial state:** redemption `reserved`; catalogue stock hits `0`/`out_of_stock` before fulfilment.
- **Actors:** Customer, System.
- **Preconditions:** `reward_redemption_status` allows `reserved→cancelled`.
- **Platform actions:** cancel reservation, return points.
- **DB writes:** `reward_redemptions.status: reserved→cancelled`; `reward_ledger` credit `kind=points, delta=+cost_points` (return); `reward_catalogue.status→out_of_stock`.
- **Status transitions:** redemption `reserved→cancelled`.
- **Notifications:** customer "reward unavailable — points returned."
- **Evidence:** none.
- **Payment impact:** none.
- **Payout impact:** none.
- **Refund/Reward impact:** points fully returned; no cash movement.
- **Completion condition:** points restored; redemption `cancelled`.
- **Failure recovery:** atomic reserve prevents oversell; `fulfilled→reserved` FORBIDDEN.
- **Audit trail:** `reward_ledger` return, `reward_redemptions`, `audit_events`.
- **Expected result:** out-of-stock reward cancels cleanly and returns points. Correct.

## 44. Inventory import contains duplicates

- **Initial state:** merchant uploads a stock CSV with duplicate product rows.
- **Actors:** Merchant, System (validate job).
- **Preconditions:** import staged; `merchant_stock_import_rows` never writes production directly.
- **Merchant actions:** upload file, run validate.
- **DB writes:** `merchant_stock_imports` header (`row_count`, `valid_count`, `error_count`); `merchant_stock_import_rows` per row with `match_product_id` (dedupe target) and `action=insert|update|skip`; duplicates resolved to `update`/`skip` against U`(merchant_id, slug)`.
- **Status transitions:** rows `staged`; on confirm `staged→applied`.
- **Notifications:** merchant validation summary (N duplicates collapsed).
- **Evidence:** import file in `market-evidence/imports/...` + `evidence_media` (`context_type=import`).
- **Payment/Payout/Refund impact:** none.
- **Completion condition:** confirm RPC bulk-upserts in one transaction; no duplicate `market_products`.
- **Failure recovery:** re-runnable validate; confirm is all-or-nothing.
- **Audit trail:** `merchant_stock_imports`, `audit_events`.
- **Expected result:** duplicates deduped in staging; production stays unique per `(merchant_id, slug)`. Correct.

## 45. Inventory import has invalid prices

- **Initial state:** import rows with negative / non-integer / zero prices.
- **Actors:** Merchant, System.
- **Preconditions:** money is integer pence, `CHECK (>=0)`; validation before apply.
- **Platform actions:** validate flags bad rows.
- **DB writes:** offending `merchant_stock_import_rows.action=error`, `validation_errors jsonb` populated, `status=staged`; header `error_count` incremented.
- **Status transitions:** invalid rows `staged→rejected` on confirm; valid rows `staged→applied`.
- **Notifications:** merchant "N rows have price errors — fix and re-upload."
- **Evidence:** import file evidence row.
- **Payment/Payout/Refund impact:** none.
- **Completion condition:** confirm applies only valid rows (or blocks if configured all-or-nothing on blocking errors).
- **Failure recovery:** merchant corrects and re-imports; staging isolates production.
- **Audit trail:** `merchant_stock_import_rows.validation_errors`, `audit_events`.
- **Expected result:** invalid prices never reach `market_products`; pence + `CHECK(>=0)` preserved. Correct.

## 46. Merchant uploads 10,000 products

- **Initial state:** large catalogue file (10k rows).
- **Actors:** Merchant, System (background job).
- **Preconditions:** import staging isolates bulk from production; ≤10 MB file.
- **Merchant actions:** upload; validate runs as a job.
- **DB writes:** 10k `merchant_stock_import_rows` staged; validated in batches; confirm bulk-upserts in **one** RPC transaction into `market_products`.
- **Status transitions:** rows `staged→applied`; import header `confirmed_at`/`confirmed_by`.
- **Notifications:** merchant progress + completion summary.
- **Evidence:** import file evidence.
- **Payment/Payout/Refund impact:** none.
- **Completion condition:** all valid rows applied; staging isolates the 10k load from hot tables (per §11 performance).
- **Failure recovery:** re-runnable validate; confirm all-or-nothing; partial batches don't corrupt production.
- **Audit trail:** `merchant_stock_imports`, `audit_events`.
- **Expected result:** large import handled in staging + one transactional apply without impacting live product reads. Correct.

## 47. Two customers buy final stock simultaneously (race)

- **Initial state:** platform item (eggs) `available_count = 1`; two orders reserve concurrently.
- **Actors:** Customer A, Customer B, Platform.
- **Preconditions:** `platform_inventory.reserved_count` guarded; `available_count = stock_count − reserved_count`; `CHECK(>=0)`.
- **Platform actions:** order RPC reserves atomically (row lock / conditional update).
- **DB writes:** winner: `reserved_count += 1`, `inventory_movements` reason=`reserve`, `balance_after` recorded. Loser: reserve fails (`available_count` would go negative → `CHECK` / conditional guard) → RPC aborts.
- **Status transitions:** winner's order created with the egg line; loser's egg line dropped or order aborted.
- **Notifications:** loser "item just sold out."
- **Evidence:** none.
- **Payment impact:** only the winner is charged for the egg line.
- **Payout impact:** none (platform-owned).
- **Refund impact:** none (loser never charged).
- **Completion condition:** exactly one reservation of the last unit.
- **Failure recovery:** loser re-prices without eggs; oversell impossible.
- **Audit trail:** `inventory_movements` (single reserve), `audit_events`.
- **Expected result:** last unit sold once; `reserved_count`/`CHECK` prevents oversell under concurrency. Correct.

## 48. Order contains products from suspended merchant

- **Initial state:** basket has items from a merchant whose `merchant_status` became `suspended` before checkout.
- **Actors:** Customer, Platform.
- **Preconditions:** order RPC re-validates merchant `active` at price/checkout.
- **Platform actions:** block that merchant's lines at pricing/order RPC.
- **DB writes:** no sub-order created for suspended merchant; basket re-priced without those lines; if already `paid` and suspension mid-flight, sub-order `→cancelled` + refund.
- **Status transitions:** suspended merchant's sub-order never created (pre-pay) or `→cancelled` (post-pay).
- **Notifications:** customer "some items unavailable"; ops.
- **Evidence:** none.
- **Payment impact:** suspended lines excluded pre-charge; re-validate min-order (£40) + `small_order_fee`/`multistore_fee` (merchant_count may drop).
- **Payout impact:** none to suspended merchant.
- **Refund impact:** refund suspended lines if discovered post-charge.
- **Completion condition:** order proceeds with remaining active merchants, or aborts if below min.
- **Failure recovery:** re-price recomputes fees and `merchant_count`.
- **Audit trail:** `audit_events`, sub-order cancel/refund if applicable.
- **Expected result:** suspended merchant excluded; fees + minimum re-validated; no payout to suspended merchant. Correct.

## 49. Merchant staff member loses access mid-order

- **Initial state:** a picker is `active` on a sub-order in `picking`; their `merchant_staff.status` set to `revoked` mid-fulfilment.
- **Actors:** Merchant owner, Revoked picker, Platform.
- **Preconditions:** every merchant-scoped RLS policy joins `merchant_staff … status='active'`.
- **Platform/Merchant actions:** owner revokes the picker.
- **DB writes:** `merchant_staff.status: active→revoked`; no change to the sub-order/items themselves.
- **Status transitions:** none forced on the order; the picker simply loses write access (RLS denies).
- **Notifications:** picker access removed; owner reassigns.
- **Evidence:** evidence already uploaded by that picker stays immutable + valid.
- **Payment/Payout/Refund impact:** none.
- **Completion condition:** another active staff member continues `picking→packed→ready`.
- **Failure recovery:** the sub-order is never orphaned — any active staff of the same merchant can continue; cross-merchant isolation unaffected.
- **Audit trail:** `merchant_staff` change, `audit_events`; prior `item_events` retained.
- **Expected result:** revoked staff instantly loses write access via RLS; order continues under another active picker. Correct.

## 50. Evidence image upload fails during picking

- **Initial state:** picker packs an item but the `item_pick` image upload fails (network/storage).
- **Actors:** Merchant picker, Platform.
- **Preconditions:** evidence insert is server-side; unique on `sha256` per context; state gated on required evidence.
- **Merchant actions:** retry upload.
- **DB writes:** failed upload → **no** `evidence_media` row committed (insert-after-success); retry inserts once; duplicate `sha256` retry is a safe skip.
- **Status transitions:** item cannot advance past the evidence-gated step (`packed`/sub-order `ready`) until a valid `evidence_media` row exists.
- **Notifications:** picker "upload failed — retry."
- **Evidence:** `item_pick` inserted only on success; no partial/orphan rows.
- **Payment/Payout/Refund impact:** none.
- **Completion condition:** valid evidence present → item/sub-order proceeds.
- **Failure recovery:** retry idempotent by `sha256`; no duplicate evidence; state machine blocks progression without evidence (`substituted`/`ready` require evidence).
- **Audit trail:** `audit_events` (upload attempt), single evidence row on success.
- **Expected result:** failed upload blocks progression, retry is idempotent, no orphaned evidence. Correct.

---

*These 50 scenarios exercise the state machines (§4.2), money model (§5), RPC/idempotency plan
(§7, §11) and RLS isolation (§6) of the technical master spec. Every money figure applies the
locked rules: £40 minimum, £1.99 small-order fee below £60, 8% collection / 12% delivery
commission, £2.99 priority, £2.99 multi-store, no mixed-order fee, and merchant paid on accepted
items only. Operations narrative → `MARKETPLACE-OPERATIONS.md`; open decisions →
`MARKETPLACE-DECISIONS.md`.*

---

## Amendment 1 scenarios (51–74)

These 24 scenarios exercise the **confirmed** Amendment 1 vocabulary: town-centre hubs (Eltham /
Dartford / Erith) and hub-based discovery separated from delivery eligibility (Context 22, C22–C24);
the 10-role DB model with super-admin bootstrap `abidoyedimeji` (Context 1, C28); three-level
delivery confirmation via `order_confirmations`/`item_confirmations` (Context 12, C29); the fully
audited **returns** lifecycle `item_returns`/`return_status` (Context 13, C30); scoped refunds with
the **service-fee-retained-by-default** rule and audited fee override (Context 13/§5, C31–C32); and
the **payout reconfirmation** loop `eligible→on_hold→recalculating→reconfirmed→eligible` (§4.2, C33).
Merchant is paid on **accepted items only** and payout **reconfirms after any return/refund**. Fee
mapping follows note N1: small-order + multi-store fees = retained service/handling; priority-window
= refundable if the priority service failed. All money in **integer pence**.

- **New enums used:** `customer_confirmation_status`: `pending, confirmed, partially_rejected,
  rejected, auto_confirmed`; `return_status`: `return_requested, return_approved, return_assigned,
  collected_from_customer, returned_to_merchant, return_confirmed, financially_reconciled,
  return_rejected`; extended `payout_status`: `pending, eligible, on_hold, recalculating,
  reconfirmed, processing, paid, failed, reversed`; `waitlist_status`: `pending, invited, activated,
  opted_out`; `merchant_suggestion_status`: `suggested, duplicate_check, research_pending, contacted,
  interested, onboarding, approved, active`; `service_area_type`: `discovery, delivery, collection,
  route`; extended `evidence_type` returns members: `return_collection, return_handover,
  return_confirmation`; milestones (`merchant_referral_milestones.milestone`): `suggestion_submitted,
  merchant_contacted, onboarding_completed, merchant_activated, first_completed_order`.

## 51. Customer accepts all items at delivery (accept_all)

- **Initial state:** delivered order, single Dartford butcher, subtotal `4500`, standard delivery; confirmation window open.
- **Actors:** Customer, System (auto-confirm job fallback).
- **Preconditions:** order `delivered`; `delivery_proof` evidence exists; no open rejection/return/refund.
- **Customer actions:** taps "accept everything" at the door → one bulk `accept_all` action.
- **DB writes:** `order_confirmations` insert (`scope=order`, `action=accept_all`, `status=confirmed`); fan-out `item_confirmations` insert per item (`decision=accepted`, `order_confirmation_id` set), U`(item_id)`; `market_order_items.item_status: delivered→accepted`; `merchant_sub_orders.accepted_subtotal_cents=4500`.
- **Status transitions:** order `delivered→completed` (window clears with all-accepted); items `delivered→accepted`; settlement `pending→eligible→...` after window; confirmation `pending→confirmed`.
- **Notifications:** customer "order confirmed"; merchant "payout pending window"; System auto-confirm skipped (already confirmed).
- **Evidence created (evidence_type):** `customer_accept` (one per accepted item / bulk).
- **Payment impact:** already charged `4500 + 199 small_order = 4699`; no change.
- **Payout impact:** `accepted_subtotal=4500`; commission `round(4500×0.120)=540`; `eligible_cents=4500−540=3960`; payout eligible only **after** confirmation window elapses (delivery alone does not release funds — C33).
- **Refund impact:** none (`0`).
- **Completion condition:** all items `accepted` + window clear → order `completed`; settlement `eligible`.
- **Failure recovery:** if customer takes no action, System auto-confirm writes `item_confirmations decision=accepted` (system actor) + `customer_confirmation_status=auto_confirmed` at window.
- **Audit trail:** `audit_events` (confirmation), `item_events` per item, `customer_accept` evidence.
- **Expected result:** merchant paid `3960`, platform keeps `540 + 199`, customer charged `4699`, payout releases post-window. Correct.

## 52. Customer rejects one item, accepts the rest (item-level)

- **Initial state:** delivered single-merchant order; item A meat `3000` + item B mince `1500`, subtotal `4500`, delivery; small_order fee `199`.
- **Actors:** Customer, Platform (ops review), Finance.
- **Preconditions:** order `delivered`; window open; per-item confirmation available (C29 — never forced to reject whole order).
- **Customer actions:** accepts A, rejects B (`reason=poor_quality`) with a photo.
- **DB writes:** `order_confirmations` (`scope=item`, `action=reject_items`, `status=partially_rejected`); `item_confirmations` A `decision=accepted`, B `decision=rejected`; `item_rejections` insert for B (`qty_rejected=1`, `status=submitted`); on approval `refunds` insert (`scope=item`, `refund_type=partial`, `product_value_cents=1500`, `fee_refund_cents=0`, `amount_cents=1500`); `market_order_items` B `item_status: delivered→rejected`, `refunded_cents=1500`; `merchant_sub_orders.accepted_subtotal_cents: 4500→3000`; `settlement_adjustments` (`amount_cents=-1500`).
- **Status transitions:** items A `delivered→accepted`, B `delivered→rejected`; rejection `submitted→under_review→approved→resolved`; refund `requested→pending_review→approved→processing→completed`; order `delivered→partially_refunded`; payout `eligible→on_hold→recalculating→reconfirmed`.
- **Notifications:** customer "item B refunded"; merchant "sub-order recalculated"; finance refund queue.
- **Evidence created (evidence_type):** `customer_reject` (item B), `customer_accept` (item A).
- **Payment impact:** original charge `4699` unchanged; refund issued separately.
- **Payout impact:** recompute on **accepted** gross `3000`: commission `round(3000×0.120)=360`; `eligible_cents=3000−360=2640` (was `3960`). Payout **reconfirmed** before release.
- **Refund impact:** `1500` product to customer; `fee_refund_cents=0` (small-order fee retained per C32). `amount_cents=1500`.
- **Completion condition:** rejection `resolved` + refund `completed` + payout `reconfirmed` → settlement `eligible`.
- **Failure recovery:** refund `processing→failed→processing` retries on same `idempotency_key`; `refunds.stripe_refund_id` U.
- **Audit trail:** `audit_events` (reject, refund approve), `item_events`, `settlement_adjustments`.
- **Expected result:** customer refunded `1500`, merchant paid `2640` on the accepted item only, small-order fee retained, payout reconfirmed. Correct.

## 53. Customer rejects items from one merchant in a multi-store order

- **Initial state:** delivered multi-store order, Merchant A meat `3000` + Merchant B meat `3000`, subtotal `6000`, delivery, multistore fee `299`.
- **Actors:** Customer, Merchant A, Merchant B, Finance.
- **Preconditions:** two `merchant_sub_orders`; customer rejects one Merchant A item worth `1500`.
- **Customer actions:** rejects a Merchant A line (`reason=damaged`); accepts everything else.
- **DB writes:** `order_confirmations` (`scope=item`, `action=reject_items`); `item_confirmations` for all items; `item_rejections` on the A line; `refunds` (`scope=item`, `product_value_cents=1500`, `fee_refund_cents=0`, `amount_cents=1500`, `sub_order_id`=A); A `merchant_sub_orders.accepted_subtotal_cents: 3000→1500`; A `settlement_adjustments` `-1500`. **Merchant B rows untouched.**
- **Status transitions:** A item `delivered→rejected`; A settlement `eligible→on_hold→recalculating→reconfirmed`; **B settlement stays `eligible`** (isolation); order `delivered→partially_refunded`.
- **Notifications:** customer refund; Merchant A recalculated; Merchant B nothing.
- **Evidence created (evidence_type):** `customer_reject` (A line), `damaged_item` on rejection.
- **Payment impact:** `6299` charge unchanged; refund separate.
- **Payout impact:** Merchant A recompute on `1500`: commission `round(1500×0.120)=180`; `eligible=1500−180=1320` (was `2640`). Merchant B unchanged: `3000−360=2640`. Multistore `299` retained.
- **Refund impact:** `1500` to customer; only Merchant A's settlement reduced; `fee_refund_cents=0`.
- **Completion condition:** A rejection resolved + A payout reconfirmed; B unaffected → both eligible.
- **Failure recovery:** cross-merchant isolation guarantees a Merchant A problem never mutates Merchant B's settlement/transfer.
- **Audit trail:** `audit_events`, `item_events` (A only), `settlement_adjustments` (A only).
- **Expected result:** customer refunded `1500`, Merchant A paid `1320`, Merchant B still `2640`, only A's settlement reduced. Correct.

## 54. Customer rejects the entire cart (reject_order fan-out)

- **Initial state:** delivered single-merchant order, subtotal `4500`, delivery, small_order fee `199`.
- **Actors:** Customer, Platform (ops), Finance.
- **Preconditions:** order `delivered`; window open; bulk `reject_order` allowed (fans to item level — truth stays item-level, C29).
- **Customer actions:** rejects the whole delivery (`reason=poor_quality`) with evidence.
- **DB writes:** `order_confirmations` (`scope=order`, `action=reject_order`, `status=rejected`); fan-out `item_confirmations decision=rejected` for **every** item; `item_rejections` per item; `refunds` (`scope=order`, `refund_type=full`, `product_value_cents=4500`, `fee_refund_cents=0`, `amount_cents=4500`); each item `item_status→rejected`, `refunded_cents` set; `merchant_sub_orders.accepted_subtotal_cents→0`; `settlement_adjustments` reducing to nil.
- **Status transitions:** all items `delivered→rejected`; order `delivered→partially_refunded` then effectively fully refunded (all lines nil); settlement `eligible→on_hold→recalculating→reconfirmed` (reconfirms to `0`).
- **Notifications:** customer "full product refund"; merchant "sub-order settled to nil"; ops dispute review.
- **Evidence created (evidence_type):** `customer_reject` per item.
- **Payment impact:** original `4699`; product `4500` refunded, service fee `199` **retained** (C32).
- **Payout impact:** `accepted_subtotal=0` → commission `round(0×0.120)=0`; `eligible_cents=0`. **All settlements → nil.**
- **Refund impact:** `product_value_cents=4500`, `fee_refund_cents=0`, `amount_cents=4500`; small-order fee `199` retained.
- **Completion condition:** all rejections resolved + refund completed + payout reconfirmed to `0`.
- **Failure recovery:** if a fee override is later warranted, follow scenario 60; otherwise fee stays retained.
- **Audit trail:** `audit_events`, one refund row scope=order, per-item `item_events`.
- **Expected result:** customer refunded `4500` product only, service fee `199` retained, merchant payout nil. Correct.

## 55. Customer requests an item return before the driver leaves

- **Initial state:** driver at the door, order `delivered`; customer wants to send back one damaged pack worth `800`; still inside the delivery interaction.
- **Actors:** Customer, Driver, Operations.
- **Preconditions:** item eligible for physical return (C30); returns are manually handled but fully represented + audited.
- **Customer actions:** requests a return on that line (`action=request_return`) before the driver departs.
- **DB writes:** `order_confirmations` (`scope=item`, `action=request_return`); `item_returns` insert (`item_id`, `target_merchant_id`, `quantity=1`, `reason='damaged'`, `status=return_requested`, `return_deadline`=end of operating day); `item_confirmations` for the line held pending return outcome; customer evidence linked (`customer_evidence_id`).
- **Status transitions:** return `return_requested` (awaiting ops approval → `return_approved`); item stays `delivered` pending physical return; no refund yet.
- **Notifications:** customer "return logged, deadline today"; ops return queue; driver "hold for return pickup".
- **Evidence created (evidence_type):** `return_collection` (customer-side / damaged item), `damaged_item`.
- **Payment impact:** none yet — money moves only on `financially_reconciled`.
- **Payout impact:** payout for that sub-order held pending return (`eligible→on_hold`); accepted_subtotal not yet reduced.
- **Refund impact:** `0` so far; refund is created at reconciliation (scenario 56).
- **Completion condition:** return progressed to `return_approved→return_assigned` within operating day.
- **Failure recovery:** if deadline slips → scenario 57; if merchant refuses → scenario 58.
- **Audit trail:** `audit_events` (return requested), `item_events`, immutable customer evidence.
- **Expected result:** return captured as `return_requested` with EOD deadline, item still in delivery flow, no premature money movement. Correct.

## 56. Driver returns the item to the merchant before end of day

- **Initial state:** approved return from scenario 55 (`item_returns.status=return_approved`), item worth `800`, within operating day.
- **Actors:** Driver (assigned operator), Merchant, Operations, Finance.
- **Preconditions:** `return_deadline` not passed; driver assigned as `assigned_operator_id`; same-day return to merchant.
- **Driver/Merchant actions:** driver collects from customer, transports to merchant, hands over; merchant confirms receipt.
- **DB writes:** `item_returns.status` walks `return_approved→return_assigned→collected_from_customer→returned_to_merchant→return_confirmed`; `merchant_confirmed_at` set; `merchant_evidence_id` set; on `financially_reconciled` a `refunds` insert (`scope=item`, `product_value_cents=800`, `fee_refund_cents=0`, `amount_cents=800`); `merchant_sub_orders.accepted_subtotal_cents −= 800`; `settlement_adjustments −800`.
- **Status transitions:** return `...→returned_to_merchant→return_confirmed→financially_reconciled`; item `delivered→rejected` (returned line generates no payout); payout `on_hold→recalculating→reconfirmed→eligible`.
- **Notifications:** customer "return complete, refund issued"; merchant "return confirmed"; finance reconciliation.
- **Evidence created (evidence_type):** `return_handover` (driver→merchant), `return_confirmation` (merchant receipt).
- **Payment impact:** `800` product refunded to customer; service fee retained.
- **Payout impact:** merchant gross drops by `800`; commission recomputed on the reduced accepted gross; payout **reconfirmed** before release (C33). `financially_reconciled` triggers settlement recalculation.
- **Refund impact:** `product_value_cents=800`, `fee_refund_cents=0`, `amount_cents=800`.
- **Completion condition:** `return_confirmed` + `financially_reconciled` + payout `reconfirmed`.
- **Failure recovery:** merchant refusal at handover → scenario 58 (`return_rejected` → dispute).
- **Audit trail:** `audit_events` per transition, `return_handover`/`return_confirmation` evidence, `settlement_adjustments`.
- **Expected result:** goods back with merchant same day, customer refunded `800` product, merchant settlement reduced and payout reconfirmed. Correct.

## 57. Return cannot be completed before end of day

- **Initial state:** approved return in transit; `return_deadline` (end of operating day) arrives with the item still at `collected_from_customer`.
- **Actors:** Driver, Operations, System (deadline check).
- **Preconditions:** returns are manual-ops; missing the deadline is an ops-handled exception, not a state-machine failure.
- **System/Ops actions:** deadline check flags the overdue return; ops carries it overnight and reschedules merchant handover next operating day.
- **DB writes:** `item_returns` stays `return_assigned`/`collected_from_customer` (no forbidden skip to `returned_to_merchant`); `admin_notes` records the overrun; **no** `refunds` row yet; no settlement change.
- **Status transitions:** return holds at `collected_from_customer` overnight; **no** `financially_reconciled`; payout stays `on_hold` (not reconfirmed).
- **Notifications:** ops "return overdue"; customer "return in progress"; finance "reconciliation pending".
- **Evidence created (evidence_type):** `return_collection` retained; `return_handover` not yet created.
- **Payment impact:** none — money waits for reconciliation.
- **Payout impact:** merchant payout remains `on_hold` (delivery-time return still open → cannot go `eligible`).
- **Refund impact:** `0` until the return confirms next day.
- **Completion condition:** next-day handover resumes `→returned_to_merchant→return_confirmed→financially_reconciled`.
- **Failure recovery:** ops reschedule; state never illegally advances; audit captures the overrun and reason.
- **Audit trail:** `audit_events` (deadline miss, `admin_notes`), `item_events`, no premature financial rows.
- **Expected result:** overnight hold with no money movement, payout stays on_hold, return resumes and reconciles the next operating day. Correct.

## 58. Merchant refuses the returned item (return_rejected → dispute)

- **Initial state:** driver presents returned item (`800`); merchant inspects and refuses it (claims not their stock / not defective).
- **Actors:** Driver, Merchant, Operations (dispute), Finance.
- **Preconditions:** `item_returns.status=return_approved`/`returned_to_merchant`; merchant refuses on inspection.
- **Merchant/Ops actions:** merchant declines receipt; ops opens a dispute; financial reconciliation is held pending resolution.
- **DB writes:** `item_returns.status→return_rejected`; `admin_notes` + merchant reason; `evidence_media.locked_at` set on the return chain (dispute opened → no further supersede); **no** `refunds` row auto-created; settlement **not** recalculated yet.
- **Status transitions:** return `return_approved→return_rejected`; linked `item_rejections` may go `under_review→merchant_disputed`; payout stays `on_hold` (reconciliation held).
- **Notifications:** customer "return under review"; merchant dispute logged; ops/finance dispute queue.
- **Evidence created (evidence_type):** `return_confirmation` refusal note, `damaged_item`; evidence chain **locked**.
- **Payment impact:** none until dispute resolves.
- **Payout impact:** held at `on_hold`; not reconfirmed while the return/dispute is open (gate forbids `eligible` with an open return).
- **Refund impact:** `0` pending decision; if ops later side with customer, a `refunds` row (`800`) + `settlement_adjustments` are created then.
- **Completion condition:** dispute resolved by ops → either refund + settlement adjustment, or return closed with no refund.
- **Failure recovery:** locked immutable evidence anchors the dispute; decision recorded with authorised actor + reason.
- **Audit trail:** `audit_events` (refusal, dispute, resolution), locked `evidence_media`, `item_events`.
- **Expected result:** refused return parks reconciliation in a dispute; no money moves and payout stays held until an authorised decision. Correct.

## 59. Refund approved but service fee retained

- **Initial state:** approved item refund; item product value `1200`; order carried small_order fee `199` (service) and no priority fee.
- **Actors:** Customer, Finance.
- **Preconditions:** default fee policy — **service fee retained** (C32, N1: small-order = retained service/handling).
- **Finance actions:** approve refund of product value only.
- **DB writes:** `refunds` insert (`scope=item`, `refund_type=partial`, `product_value_cents=1200`, `fee_refund_cents=0`, `is_fee_override=false`, `amount_cents=1200`); `market_order_items.refunded_cents=1200`, `item_status→rejected`; `merchant_sub_orders.accepted_subtotal_cents −= 1200`; `settlement_adjustments −1200`.
- **Status transitions:** refund `requested→pending_review→approved→processing→completed`; payout `eligible→on_hold→recalculating→reconfirmed`.
- **Notifications:** customer "£12.00 refunded, service fee retained"; finance ledger.
- **Evidence created (evidence_type):** `customer_reject`/`damaged_item` as basis.
- **Payment impact:** `1200` returned; `199` small-order fee kept as platform revenue.
- **Payout impact:** merchant gross reduced by `1200`; commission recomputed on reduced accepted gross; payout reconfirmed.
- **Refund impact:** `product_value_cents=1200`, `fee_refund_cents=0`, `amount_cents=1200`. Worked: customer out-of-pocket net includes the retained `199`.
- **Completion condition:** refund `completed` + payout `reconfirmed`.
- **Failure recovery:** Stripe failure retries on same `idempotency_key`; `stripe_refund_id` U prevents double refund.
- **Audit trail:** `audit_events` (approve), `refunds` row with `is_fee_override=false`, `settlement_adjustments`.
- **Expected result:** exactly `1200` refunded, service fee `199` retained by default, no override recorded. Correct.

## 60. Admin overrides and refunds the service fee

- **Initial state:** same `1200` item refund as scenario 59, but the service failure warrants refunding the `199` small-order fee too.
- **Actors:** Customer, Finance staff / Platform admin (authorised override only).
- **Preconditions:** override requires role ≥ `finance_staff`/`platform_admin`; mandatory reason + amount + timestamp + audit (C32, §5).
- **Admin actions:** authorises a fee override on the small-order fee component.
- **DB writes:** `refunds` insert/update (`product_value_cents=1200`, `fee_refund_cents=199`, `is_fee_override=true`, `fee_override_component='small_order_fee'`, `fee_override_reason` set, `fee_override_by`=finance user, `amount_cents=1399`); `settlement_adjustments −1200` (fee is platform-side, not merchant gross).
- **Status transitions:** refund `approved→processing→completed`; payout `eligible→on_hold→recalculating→reconfirmed`.
- **Notifications:** customer "£13.99 refunded incl. service fee"; finance override log.
- **Evidence created (evidence_type):** original rejection evidence + override note (audit, not media).
- **Payment impact:** `1399` returned (`1200` product + `199` fee).
- **Payout impact:** merchant gross reduced by product `1200` only (fee never was merchant gross); commission recomputed; payout reconfirmed. Fee refund is a **platform** write-off, not a merchant adjustment.
- **Refund impact:** `product_value_cents=1200`, `fee_refund_cents=199`, `amount_cents=1399`, `is_fee_override=true`.
- **Completion condition:** refund `completed` with full override audit present (actor + reason + amount + timestamp).
- **Failure recovery:** RPC rejects the override if actor role < finance/admin or if reason/amount missing.
- **Audit trail:** mandatory `audit_events` row for the override (enforced), `refunds.fee_override_by/reason`.
- **Expected result:** `1399` refunded with a fully audited fee override; only finance/admin could authorise; merchant gross reduced by product only. Correct.

## 61. Merchant settlement recalculated after item rejection

- **Initial state:** merchant sub-order gross `5000` (delivery), settlement already computed; one item worth `1000` rejected post-delivery.
- **Actors:** Customer, Finance, System (settlement recalc).
- **Preconditions:** payout not yet paid; rejection approved; recompute on accepted items only (C14/C33).
- **Customer/Finance actions:** rejection approved → refund `1000` → settlement recalc triggered.
- **DB writes:** `merchant_sub_orders.accepted_subtotal_cents: 5000→4000`; `refunds` (`product_value_cents=1000`, `amount_cents=1000`); `merchant_settlements.commission_cents` recomputed; `merchant_settlements.eligible_cents` recomputed; `settlement_adjustments −1000`.
- **Status transitions:** payout `on_hold→recalculating→reconfirmed`; item `delivered→rejected`.
- **Notifications:** merchant "settlement recalculated"; finance.
- **Evidence created (evidence_type):** `customer_reject` basis.
- **Payment impact:** `1000` refunded to customer; fees retained.
- **Payout impact (worked):** was `gross 5000 − round(5000×0.120)=600 = eligible 4400`; now `gross_accepted 4000 − round(4000×0.120)=480 = eligible 3520`. Commission recomputed **once** on accepted gross (never re-rounded per item).
- **Refund impact:** `1000` product; `fee_refund_cents=0`.
- **Completion condition:** settlement `reconfirmed` with `eligible_cents=3520`.
- **Failure recovery:** recompute is idempotent from current accepted lines; adjustments append, never overwrite prior figures.
- **Audit trail:** `audit_events`, `settlement_adjustments`, `merchant_settlements` history via events.
- **Expected result:** accepted_subtotal `4000`, commission `480`, eligible `3520`; payout on_hold→recalculating→reconfirmed. Correct.

## 62. Eligible payout becomes held after a late delivery-time issue

- **Initial state:** sub-order delivered, confirmation window looked clear, settlement already `eligible` at `3960` (gross `4500`, commission `540`); then a late delivery-time issue (short-dated item worth `900`) is raised inside the window.
- **Actors:** Customer, Finance, System.
- **Preconditions:** payout `eligible` but **not yet** `processing`/`paid`; any delivery-time return/refund/rejection forces reconfirmation (C33).
- **Customer/Finance actions:** customer reports the item; refund `900` approved.
- **DB writes:** `refunds` (`product_value_cents=900`, `amount_cents=900`); `merchant_sub_orders.accepted_subtotal_cents: 4500→3600`; `settlement_adjustments −900`; `merchant_settlements.eligible_cents` recomputed.
- **Status transitions:** payout `eligible→on_hold→recalculating→reconfirmed→eligible` (full loop); item `delivered→rejected`.
- **Notifications:** merchant "payout recalculated before release"; finance.
- **Evidence created (evidence_type):** `customer_reject`/`damaged_item`.
- **Payment impact:** `900` refunded; fees retained.
- **Payout impact (worked):** recompute on `3600`: commission `round(3600×0.120)=432`; `eligible_cents=3600−432=3168` (was `3960`). Reconfirmed value released only after the loop closes.
- **Refund impact:** `900` product; `fee_refund_cents=0`.
- **Completion condition:** payout back to `eligible` at `3168` after reconfirmation; then `processing→paid`.
- **Failure recovery:** because it was not yet `paid`, no clawback needed; had it been paid, `paid→reversed` (rare, flagged) applies.
- **Audit trail:** `audit_events` (hold, recalc, reconfirm), `settlement_adjustments`.
- **Expected result:** previously-eligible payout correctly forced through `on_hold→recalculating→reconfirmed→eligible`, landing at `3168`. Correct.

## 63. Full order refund across multiple merchants

- **Initial state:** delivered multi-store order, Merchant A `3000` + Merchant B `3000`, subtotal `6000`, multistore fee `299`, delivery.
- **Actors:** Customer, Operations, Finance.
- **Preconditions:** whole-order rejection approved; two sub-orders each settle to nil; service fees retained unless override (C32).
- **Customer actions:** rejects the entire order (`action=reject_order`).
- **DB writes:** `order_confirmations` (`scope=order`, `action=reject_order`); fan-out `item_confirmations decision=rejected`; **N=2** `refunds` rows (one per sub-order: A `product_value_cents=3000`, B `product_value_cents=3000`, each `fee_refund_cents=0`, `amount_cents=3000`); both `merchant_sub_orders.accepted_subtotal_cents→0`; two `settlement_adjustments` to nil.
- **Status transitions:** all items `delivered→rejected`; both settlements `eligible→on_hold→recalculating→reconfirmed` (to `0`); order `delivered→partially_refunded` (fully, product-wise).
- **Notifications:** customer full product refund; both merchants "settled to nil"; finance.
- **Evidence created (evidence_type):** `customer_reject` per item.
- **Payment impact:** product `6000` refunded (`3000`+`3000`); multistore fee `299` **retained**.
- **Payout impact:** each merchant `accepted_subtotal=0` → commission `0` → `eligible_cents=0`; **no transfers**.
- **Refund impact:** two refunds totalling `6000` product; `fee_refund_cents=0` each; `299` retained.
- **Completion condition:** both settlements reconfirmed to `0`; both refunds `completed`.
- **Failure recovery:** each merchant's refund/adjustment is independent + idempotent; one failing does not block the other.
- **Audit trail:** `audit_events`, two `refunds`, two `settlement_adjustments`, per-item `item_events`.
- **Expected result:** customer refunded `6000` product, multistore `299` retained, both merchant payouts nil, N=2 refunds. Correct.

## 64. Platform-owned eggs refunded while merchant goods are accepted

- **Initial state:** delivered mixed order — merchant meat `4000` (accepted) + platform eggs `500` (bad on arrival), delivery, small_order fee `199`.
- **Actors:** Customer, Platform (inventory/finance), Merchant (unaffected).
- **Preconditions:** eggs are on the **platform sub-order** (`merchant_id=null`); merchant sub-order fulfilled fine (A5).
- **Customer actions:** accepts merchant meat, rejects the platform egg line.
- **DB writes:** `item_confirmations` meat `accepted`, eggs `rejected`; `refunds` (`scope=item`, `sub_order_id`=platform sub-order, `product_value_cents=500`, `fee_refund_cents=0`, `amount_cents=500`); platform sub-order `accepted_subtotal_cents: 500→0`; `inventory_movements` reason=`adjust` (write-off the bad eggs). **Merchant sub-order untouched.**
- **Status transitions:** egg item `delivered→rejected`; merchant items `delivered→accepted`; **no** merchant payout state change; order `delivered→partially_refunded`.
- **Notifications:** customer "eggs refunded"; ops inventory; merchant nothing.
- **Evidence created (evidence_type):** `customer_reject`/`damaged_item` on the egg line.
- **Payment impact:** `500` refunded (platform absorbs, platform-owned goods); merchant meat charge stands.
- **Payout impact:** **none to merchant** — commission `round(4000×0.120)=480`, `eligible=4000−480=3520` unchanged. Platform eats its own eggs' cost via `inventory_movements` write-off; no `merchant_settlements`/`settlement_adjustments` on any merchant.
- **Refund impact:** `product_value_cents=500`, `fee_refund_cents=0`, `amount_cents=500` (platform-side write-off).
- **Completion condition:** egg refund `completed`; merchant settlement stays `eligible` at `3520`.
- **Failure recovery:** platform inventory decides restock vs write-off; merchant flow never re-opens.
- **Audit trail:** `audit_events`, `inventory_movements` (reason=adjust), `refunds`.
- **Expected result:** eggs refunded `500` against the platform sub-order only; merchant paid `3520` normally with zero payout impact. Correct.

## 65. Water returned due to damage

- **Initial state:** delivered order includes platform water `1000` (delivery-only, platform-owned); customer reports leaking/damaged bottles and requests a return.
- **Actors:** Customer, Driver, Platform (inventory/ops).
- **Preconditions:** water is on the platform sub-order; returns manual-ops (C30); platform decides restock vs write-off.
- **Customer/Driver actions:** return requested; driver collects damaged water from customer.
- **DB writes:** `item_returns` insert (`target_merchant_id=null` — platform sub-order, `quantity`, `reason='damaged'`, `status=return_requested→...→return_confirmed→financially_reconciled`, `return_deadline`=EOD); `refunds` (`scope=item`, platform sub-order, `product_value_cents=1000`, `amount_cents=1000`); `inventory_movements` reason=`adjust` (write-off) **or** `restock` if resellable (platform decision, `balance_after` updated).
- **Status transitions:** return `return_requested→return_approved→return_assigned→collected_from_customer→returned_to_merchant→return_confirmed→financially_reconciled`; water item `delivered→rejected`.
- **Notifications:** customer "water refunded"; ops inventory decision; driver pickup task.
- **Evidence created (evidence_type):** `damaged_item`, `return_collection`, `return_confirmation`.
- **Payment impact:** `1000` refunded (platform absorbs).
- **Payout impact:** none — platform-owned; **no merchant settlement/transfer touched**.
- **Refund impact:** `product_value_cents=1000`, `fee_refund_cents=0`, `amount_cents=1000`.
- **Completion condition:** return `financially_reconciled` + inventory movement recorded (restock or writeoff).
- **Failure recovery:** if bottles resellable → `inventory_movements reason=restock` returns stock; if not → `reason=adjust` write-off.
- **Audit trail:** `audit_events`, `item_returns` chain, `inventory_movements`, `refunds`.
- **Expected result:** damaged water returned and refunded `1000` on the platform sub-order; inventory restock/writeoff logged; no merchant impact. Correct.

## 66. Customer joins the Eltham waitlist

- **Initial state:** authenticated user whose postcode maps to the **Eltham** hub, which is not yet live for ordering.
- **Actors:** Customer, System (demand count), Operations (later invite).
- **Preconditions:** hub `launch_areas` row for Eltham (`is_hub=true`); one active membership per user/email per hub (partial-unique, C25); **no votes counter**.
- **Customer actions:** submits postcode + email to join the waitlist.
- **DB writes:** `location_waitlist` insert (`launch_area_id`=Eltham, `status=pending`, `postcode`, `source`, `referral_code` nullable, `joined_at=now()`); U`(user_id, launch_area_id)` / U`(lower(email), launch_area_id)` WHERE status in (`pending`,`invited`) prevents a duplicate active row.
- **Status transitions:** waitlist `pending` (later `invited→activated`, or `opted_out` if they leave).
- **Notifications:** customer "you're on the Eltham list"; ops demand dashboard.
- **Evidence created (evidence_type):** none.
- **Payment impact:** none.
- **Payout impact:** none.
- **Refund impact:** none (`0`).
- **Completion condition:** row `pending`; **demand for Eltham = COUNT of rows WHERE status in (`pending`,`invited`)** for that hub (no mutable counter).
- **Failure recovery:** a repeat join by the same user/email for Eltham is a safe no-op (partial-unique); joining a *different* hub is a separate allowed row.
- **Audit trail:** `audit_events` (join), `location_waitlist` timestamps.
- **Expected result:** one active Eltham membership at `pending`; demand computed by counting active entries, not a votes field. Correct.

## 67. Customer postcode maps to more than one discovery hub

- **Initial state:** a postcode that falls inside the 5-mile discovery radius of **both** Eltham and Erith hubs.
- **Actors:** Customer, System (nearest-hub compute).
- **Preconditions:** discovery = `ST_DWithin` from each hub centroid; nearest hub chosen at address save (N4 default: nearest live hub, list others).
- **Customer actions:** saves an address.
- **DB writes:** `user_addresses` insert with `location`; compute `nearest_hub_id` = closest hub by `hub_distance_m`; `hub_distance_m` stored (computed at save, never at query time).
- **Status transitions:** none (geography, not order lifecycle).
- **Notifications:** customer "your hub: Eltham (nearest); also near Erith".
- **Evidence created (evidence_type):** none.
- **Payment impact:** none.
- **Payout impact:** none.
- **Refund impact:** none.
- **Completion condition:** `nearest_hub_id` set to the closest **live** hub; other in-range hubs surfaced as alternatives (N4).
- **Failure recovery:** if the nearest hub is not live, fall back to the nearest live hub in range; if none live, offer waitlist (scenario 66).
- **Audit trail:** `audit_events` (address save), stored `nearest_hub_id`/`hub_distance_m`.
- **Expected result:** deterministic nearest-hub assignment with alternatives listed; distance precomputed at save. Correct (pending N4 UX ratification).

## 68. Inside five-mile discovery but outside the delivery service zone

- **Initial state:** customer postcode inside the Dartford hub's 5-mile `discovery` zone but **outside** any active `delivery` zone / live route.
- **Actors:** Customer, System (eligibility checks).
- **Preconditions:** discovery ≠ delivery eligibility (C19/C23); delivery re-checked at basket-price time, not just discovery.
- **Customer actions:** browses (discovery passes), then tries to price a delivery basket.
- **DB writes:** none committed for the blocked delivery order; basket may fall back to `collection` if inside a `collection` zone + a merchant with `collection_enabled`.
- **Status transitions:** basket stays `open`/re-`priced` without a delivery method; no `market_orders` row for delivery.
- **Notifications:** customer "discovery yes, delivery not available here yet"; offer collection if eligible; else waitlist.
- **Evidence created (evidence_type):** none.
- **Payment impact:** none (order blocked pre-charge).
- **Payout impact:** none.
- **Refund impact:** none.
- **Completion condition:** delivery blocked because `ST_Covers` on the active `delivery` zone fails / no active `route` zone; collection offered where valid.
- **Failure recovery:** customer switches to collection (if in a `collection` zone) or joins the hub waitlist for delivery expansion.
- **Audit trail:** `audit_events` (eligibility check outcome).
- **Expected result:** discovery via `ST_DWithin` from the hub succeeds while delivery is correctly blocked at the price step; collection offered when applicable. Correct.

## 69. Customer suggests a duplicate merchant

- **Initial state:** customer suggests a butcher already present (as an active merchant or an existing suggestion).
- **Actors:** Customer, Operations (dedupe), System (duplicate detection).
- **Preconditions:** dedupe via `lower(merchant_name)` + GiST `location`; reward never on submission (C27).
- **Customer actions:** submits a merchant suggestion (name/address/category/contact).
- **DB writes:** `merchant_suggestions` insert then `status=duplicate_check`; detection sets `duplicate_of` = the existing suggestion/merchant; **no** new `merchant_referral_milestones` row beyond nothing rewardable; no `reward_ledger` entry.
- **Status transitions:** suggestion `suggested→duplicate_check` (parks as duplicate); **no** `suggestion_submitted` reward-bearing progression toward onboarding.
- **Notifications:** customer "already on our radar — thanks"; ops dedupe log.
- **Evidence created (evidence_type):** none.
- **Payment impact:** none.
- **Payout impact:** none.
- **Refund impact:** none.
- **Completion condition:** `duplicate_of` set; no milestone reached, no reward accrued.
- **Failure recovery:** if dedupe was wrong, ops clears `duplicate_of` and lets the lifecycle proceed normally.
- **Audit trail:** `audit_events` (dedupe decision), `merchant_suggestions.duplicate_of`.
- **Expected result:** duplicate parked with `duplicate_of` set, no new milestone, no reward. Correct.

## 70. Customer-generated merchant QR code results in onboarding

- **Initial state:** customer shares their referral QR/URL with a local merchant who scans it and later onboards.
- **Actors:** Customer (referrer), Merchant, Operations, System (rewards).
- **Preconditions:** attribution via `referral_url`/`qr_code_path`; rewards accrue only at `onboarding_completed`+ (C27, never on submission).
- **Customer/Merchant actions:** merchant scans QR → suggestion attributed → ops progress the merchant to activation.
- **DB writes:** `merchant_suggestions` insert (`referral_url`, `qr_code_path`, `referrer_user_id`); `merchant_referral_milestones` rows appended as reached: `suggestion_submitted`(no reward) → `merchant_contacted` → `onboarding_completed` (reward accrues) → `merchant_activated`; `merchant_suggestions.onboarded_merchant_id` set; `reward_ledger` insert (`kind=points`) at `onboarding_completed`; `merchant_suggestions.status` walks `suggested→...→onboarding→approved→active`.
- **Status transitions:** milestones `suggestion_submitted→merchant_contacted→onboarding_completed→merchant_activated`; suggestion lifecycle to `active`.
- **Notifications:** referrer "your merchant onboarded — points earned"; ops onboarding.
- **Evidence created (evidence_type):** none (media); milestones + ledger are the record.
- **Payment impact:** none.
- **Payout impact:** none (merchant payouts are order-driven, separate).
- **Refund impact:** none.
- **Completion condition:** `onboarding_completed`/`merchant_activated` reached → `merchant_referral_milestones.rewarded=true`, points in `reward_ledger` (whole points, no cash value — C13).
- **Failure recovery:** if onboarding stalls before `onboarding_completed`, no reward accrues (scenario 71).
- **Audit trail:** `audit_events`, `merchant_referral_milestones` (U per `(suggestion_id, milestone)`), `reward_ledger`.
- **Expected result:** QR-attributed onboarding accrues referrer points at `onboarding_completed`+, merchant reaches `active`. Correct.

## 71. Merchant referral submitted but merchant never activates

- **Initial state:** customer submits a merchant suggestion; the merchant is contacted but declines / goes cold — never onboards.
- **Actors:** Customer (referrer), Operations, System.
- **Preconditions:** reward gated on `onboarding_completed`+ (C27); submission alone earns nothing.
- **Customer/Ops actions:** suggestion submitted; ops attempt contact; merchant does not proceed.
- **DB writes:** `merchant_suggestions` insert; `merchant_referral_milestones` row `suggestion_submitted` only (optionally `merchant_contacted`); **no** `onboarding_completed`/`merchant_activated` rows; **no** `reward_ledger` entry.
- **Status transitions:** suggestion `suggested→contacted` then stalls (may end `research_pending`); milestone chain stops before any reward-bearing stage.
- **Notifications:** ops "merchant declined"; referrer no reward notification.
- **Evidence created (evidence_type):** none.
- **Payment impact:** none.
- **Payout impact:** none.
- **Refund impact:** none.
- **Completion condition:** only `suggestion_submitted` (and maybe `merchant_contacted`) reached; `rewarded=false`; **no completed-referral reward**.
- **Failure recovery:** if the merchant later revives, the same suggestion can progress and reward then (milestones U per stage prevent double-award).
- **Audit trail:** `audit_events`, `merchant_referral_milestones` (submission only), empty reward ledger for this referral.
- **Expected result:** no reward because no reward-bearing milestone was reached. Correct.

## 72. Merchant activates but generates no completed orders

- **Initial state:** referred merchant reaches `merchant_activated`, but never fulfils a first completed order.
- **Actors:** Customer (referrer), Merchant, System (rewards).
- **Preconditions:** `merchant_activated` is a reward-bearing milestone; `first_completed_order` is a separate later milestone.
- **Merchant actions:** goes live but has zero completed marketplace orders.
- **DB writes:** `merchant_referral_milestones` rows up to `merchant_activated` (reward per C27 at activation); **no** `first_completed_order` row; any reward tied specifically to a first completed order is **not** written.
- **Status transitions:** milestones stop at `merchant_activated`; `first_completed_order` **not reached**.
- **Notifications:** referrer "activation reward"; no first-order reward.
- **Evidence created (evidence_type):** none.
- **Payment impact:** none.
- **Payout impact:** none.
- **Refund impact:** none.
- **Completion condition:** `merchant_activated` rewarded (if that stage carries a reward); `first_completed_order` remains unreached and unrewarded.
- **Failure recovery:** when the merchant later completes a first order, `first_completed_order` milestone is appended and any first-order reward accrues then (U prevents duplication).
- **Audit trail:** `audit_events`, `merchant_referral_milestones` (through `merchant_activated`), `reward_ledger` for reached stages only.
- **Expected result:** activation-stage reward accrues; first-order reward correctly withheld until `first_completed_order`. Correct.

## 73. Super-admin assigns the first merchant admin

- **Initial state:** freshly onboarded merchant with no staff; super-admin bootstrap identity **`abidoyedimeji`** seeded in `platform_staff` (`role=super_admin`).
- **Actors:** Super-admin (`platform_staff.super_admin`), new merchant admin user.
- **Preconditions:** DB-backed roles mandatory (C28); `merchant_staff` is the per-merchant assignment + isolation boundary; privileged write via RPC/service-role after authz.
- **Super-admin actions:** creates the first `merchant_admin` assignment for that merchant.
- **DB writes:** `merchant_staff` insert (`merchant_id`, `user_id`, `role=merchant_admin`, `status=invited`→`active`, `invited_by`=super_admin); U`(merchant_id, user_id)`; `audit_events` row for the privileged role grant.
- **Status transitions:** merchant_staff `invited→active`; no order lifecycle change.
- **Notifications:** new admin "you now manage <merchant>"; super-admin confirmation.
- **Evidence created (evidence_type):** none (audit is the record).
- **Payment impact:** none.
- **Payout impact:** none.
- **Refund impact:** none.
- **Completion condition:** `merchant_staff` row `active`; the admin can now manage **only** that assigned merchant.
- **Failure recovery:** only `super_admin`/`platform_admin` may write `platform_staff`/high-level assignments; non-authorised callers are denied by RLS + RPC authz.
- **Audit trail:** `audit_events` (role grant, actor=super_admin `abidoyedimeji`), `merchant_staff` timestamps.
- **Expected result:** first merchant admin provisioned by the super-admin, scoped to one merchant, fully audited. Correct.

## 74. Merchant admin attempts to access another merchant's data

- **Initial state:** `merchant_admin` active for Merchant A tries to read Merchant B's sub-orders/products/settlements/customers.
- **Actors:** Merchant A admin (attacker context), Platform (RLS/audit).
- **Preconditions:** every merchant-scoped policy joins `merchant_staff … status='active'` on the row's `merchant_id`; cross-merchant isolation mandatory (C28, §6).
- **Merchant A admin actions:** issues queries/writes targeting Merchant B rows.
- **DB writes:** **none** — the `EXISTS(select 1 from merchant_staff ms where ms.merchant_id = <B row>.merchant_id and ms.user_id=auth.uid() and status='active')` predicate fails; RLS denies read/write; a denied-access `audit_events` row is written server-side.
- **Status transitions:** none (access denied; no state change to any Merchant B entity).
- **Notifications:** ops/security "cross-merchant access denied" (if alerting enabled).
- **Evidence created (evidence_type):** none; the audit event is the record.
- **Payment impact:** none.
- **Payout impact:** none — Merchant B settlements/transfers never resolve for Merchant A.
- **Refund impact:** none.
- **Completion condition:** zero rows returned/written for Merchant B; isolation holds.
- **Failure recovery:** deny-by-default means even a policy gap fails closed; `market_orders` is never exposed whole to a merchant (only its own sub-orders + minimum customer data).
- **Audit trail:** `audit_events` (denied cross-merchant access, actor, entity_type/id attempted).
- **Expected result:** Merchant A admin sees nothing of Merchant B; RLS join fails, access denied, attempt audited, isolation intact. Correct.
