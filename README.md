# 🎬 Location Rights Tokenization

Tokenize film shooting locations so cities and private landowners can issue on-chain location rights, set rates, accept bookings, and receive payments.

## ✨ What it does
- Mint unique location-rights NFTs for filming spots
- Set daily rates, availability, and details
- Book locations for date ranges and pay on-chain
- Rate locations and track stats
- Transfer ownership and toggle listing status
- Platform fee collection for marketplace sustainability

## 🔧 Key Functions

- mint-location(name, address, city, country, location-type, daily-rate, royalty-percentage)
- set-location-details(location-id, description, amenities, restrictions, square-footage, max-crew-size, parking-available, power-available, insurance-required)
- book-location(location-id, start-date, end-date)
- rate-location(location-id, rating, review)
- update-location-price(location-id, new-daily-rate)
- toggle-location-status(location-id)
- transfer-location(location-id, new-owner)
- withdraw-platform-fees()

Read-only:
- get-location(location-id)
- get-location-details(location-id)
- get-location-stats(location-id)
- get-booking(booking-id)
- get-user-bookings-data(user)
- get-owner-locations-data(owner)
- get-location-rating(location-id, rater)
- get-availability(location-id, date)
- get-platform-fees()

## 🚀 Usage

Mint a location:
```clarity
(contract-call? .location-rights-tokenization mint-location
  u"Old Town Square"
  u"123 Heritage Rd"
  "Prague"
  "Czechia"
  "Square"
  u5000000
  u10)

