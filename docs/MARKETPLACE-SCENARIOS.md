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
