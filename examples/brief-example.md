# 1013 acme-app: fix checkout total

The human (verbatim): "checkout shows the wrong total when a coupon is applied, fix it before Friday"

## GOAL
Customers see the right total with a coupon. Friday is the deadline; say early if it's at risk.

## CONTEXT
- Repo: ~/code/acme-app (branch from main)
- Totals: src/cart/total.ts; coupons: src/cart/coupon.ts

## DONE-WHEN
- Unit test for coupon + tax order passes; e2e checkout with coupon green on the preview.
- Screenshot of the preview checkout total attached.

## LIMITS
- Branch + preview only. No merge or prod deploy without the human. Test-mode payments only.

## REPORT
`report acme-app done "<line>" <preview link> <screenshot>`

## UPDATE 1
The human (verbatim): "also check the 'free shipping' coupon". PRIORITY: after the total fix.
