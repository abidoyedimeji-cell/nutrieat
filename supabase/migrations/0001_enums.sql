-- NutriEat — enums
-- Only values that are stable and controlled. Recipe categories are rows (see 0002).

create extension if not exists pgcrypto with schema extensions;

create type product_status as enum ('draft', 'active', 'archived');

create type product_type as enum ('physical_book', 'pdf', 'bundle');

create type order_status as enum (
  'pending', 'paid', 'payment_failed', 'cancelled',
  'refunded', 'partially_refunded', 'fulfilled'
);

create type fulfilment_status as enum (
  'not_required', 'pending', 'processing', 'shipped',
  'delivered', 'failed', 'returned'
);

create type content_status as enum ('draft', 'scheduled', 'published', 'archived');

create type lead_source as enum (
  'homepage', 'early_access', 'survey', 'blog', 'recipe',
  'instagram', 'facebook', 'youtube', 'email', 'qr_code', 'referral', 'other'
);

create type involvement_level as enum (
  'observer', 'feedback', 'voter', 'recipe_tester', 'contributor', 'high_involvement'
);

create type shipping_zone as enum ('uk', 'international');

create type recipe_visibility as enum ('public_preview', 'cookbook_only');
