(define-non-fungible-token location-rights uint)
(define-fungible-token location-token)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-location-not-found (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-location-exists (err u104))
(define-constant err-invalid-dates (err u105))
(define-constant err-booking-conflict (err u106))
(define-constant err-already-booked (err u107))
(define-constant err-invalid-percentage (err u108))
(define-constant err-listing-not-active (err u109))
(define-constant err-invalid-price (err u110))
(define-constant err-transfer-failed (err u111))
(define-constant err-discount-not-found (err u112))
(define-constant err-discount-expired (err u113))
(define-constant err-discount-inactive (err u114))
(define-constant err-min-bookings-not-met (err u115))

(define-constant platform-fee-percentage u3)
(define-constant max-royalty-percentage u20)
(define-constant min-booking-duration u1)
(define-constant max-booking-duration u365)

(define-data-var location-id-nonce uint u1)
(define-data-var booking-id-nonce uint u1)
(define-data-var total-platform-fees uint u0)
(define-data-var discount-id-nonce uint u1)

(define-map locations uint {
    owner: principal,
    name: (string-utf8 100),
    address: (string-utf8 200),
    city: (string-ascii 50),
    country: (string-ascii 50),
    location-type: (string-ascii 30),
    daily-rate: uint,
    royalty-percentage: uint,
    is-active: bool,
    total-bookings: uint,
    total-earnings: uint,
    created-at: uint
})

(define-map location-details uint {
    location-id: uint,
    description: (string-utf8 500),
    amenities: (string-utf8 300),
    restrictions: (string-utf8 300),
    square-footage: uint,
    max-crew-size: uint,
    parking-available: bool,
    power-available: bool,
    insurance-required: bool
})

(define-map bookings uint {
    booking-id: uint,
    location-id: uint,
    renter: principal,
    start-date: uint,
    end-date: uint,
    daily-rate: uint,
    total-cost: uint,
    status: (string-ascii 20),
    booked-at: uint
})

(define-map location-availability { location-id: uint, date: uint } {
    is-available: bool,
    booking-id: (optional uint)
})

(define-map location-ratings { location-id: uint, rater: principal } {
    rating: uint,
    review: (optional (string-utf8 200)),
    rated-at: uint
})

(define-map location-stats uint {
    total-bookings: uint,
    average-rating: uint,
    total-ratings: uint,
    occupancy-rate: uint,
    last-booking: uint
})

(define-map user-bookings principal {
    booking-ids: (list 100 uint),
    total-spent: uint
})

(define-map owner-locations principal {
    location-ids: (list 50 uint),
    total-earnings: uint
})

(define-map discounts uint {
    discount-id: uint,
    location-id: uint,
    discount-percentage: uint,
    valid-from: uint,
    valid-until: uint,
    min-bookings: uint,
    max-uses: uint,
    current-uses: uint,
    is-active: bool,
    created-by: principal
})

(define-public (mint-location
    (name (string-utf8 100))
    (address (string-utf8 200))
    (city (string-ascii 50))
    (country (string-ascii 50))
    (location-type (string-ascii 30))
    (daily-rate uint)
    (royalty-percentage uint))
  (let ((location-id (var-get location-id-nonce)))
    (asserts! (> daily-rate u0) err-invalid-price)
    (asserts! (<= royalty-percentage max-royalty-percentage) err-invalid-percentage)
    
    (try! (nft-mint? location-rights location-id tx-sender))
    
    (map-set locations location-id {
        owner: tx-sender,
        name: name,
        address: address,
        city: city,
        country: country,
        location-type: location-type,
        daily-rate: daily-rate,
        royalty-percentage: royalty-percentage,
        is-active: true,
        total-bookings: u0,
        total-earnings: u0,
        created-at: stacks-block-height
    })
    
    (map-set location-stats location-id {
        total-bookings: u0,
        average-rating: u0,
        total-ratings: u0,
        occupancy-rate: u0,
        last-booking: u0
    })
    
    (let ((owner-data (default-to { location-ids: (list), total-earnings: u0 } 
                                  (map-get? owner-locations tx-sender))))
        (map-set owner-locations tx-sender {
            location-ids: (unwrap! (as-max-len? (append (get location-ids owner-data) location-id) u50) err-transfer-failed),
            total-earnings: (get total-earnings owner-data)
        }))
    
    (var-set location-id-nonce (+ location-id u1))
    (ok location-id)))

(define-public (set-location-details
    (location-id uint)
    (description (string-utf8 500))
    (amenities (string-utf8 300))
    (restrictions (string-utf8 300))
    (square-footage uint)
    (max-crew-size uint)
    (parking-available bool)
    (power-available bool)
    (insurance-required bool))
  (let ((location (unwrap! (map-get? locations location-id) err-location-not-found)))
    (asserts! (is-eq tx-sender (get owner location)) err-not-authorized)
    
    (map-set location-details location-id {
        location-id: location-id,
        description: description,
        amenities: amenities,
        restrictions: restrictions,
        square-footage: square-footage,
        max-crew-size: max-crew-size,
        parking-available: parking-available,
        power-available: power-available,
        insurance-required: insurance-required
    })
    (ok true)))

(define-public (book-location
    (location-id uint)
    (start-date uint)
    (end-date uint))
  (let (
    (location (unwrap! (map-get? locations location-id) err-location-not-found))
    (booking-id (var-get booking-id-nonce))
    (duration (- end-date start-date))
    (base-cost (* (get daily-rate location) duration))
    (platform-fee (/ (* base-cost platform-fee-percentage) u100))
    (owner-payment (- base-cost platform-fee))
    (total-cost base-cost))
    
    (asserts! (get is-active location) err-listing-not-active)
    (asserts! (> end-date start-date) err-invalid-dates)
    (asserts! (>= duration min-booking-duration) err-invalid-dates)
    (asserts! (<= duration max-booking-duration) err-invalid-dates)
    (asserts! (default-to true (get is-available (map-get? location-availability { location-id: location-id, date: start-date }))) err-booking-conflict)
    
    (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
    (try! (as-contract (stx-transfer? owner-payment tx-sender (get owner location))))
    
    (map-set bookings booking-id {
        booking-id: booking-id,
        location-id: location-id,
        renter: tx-sender,
        start-date: start-date,
        end-date: end-date,
        daily-rate: (get daily-rate location),
        total-cost: total-cost,
        status: "confirmed",
        booked-at: stacks-block-height
    })
    
    (map-set location-availability 
        { location-id: location-id, date: start-date }
        { is-available: false, booking-id: (some booking-id) })
    
    (map-set locations location-id
        (merge location { 
            total-bookings: (+ (get total-bookings location) u1),
            total-earnings: (+ (get total-earnings location) owner-payment)
        }))
    
    (let ((stats (unwrap! (map-get? location-stats location-id) err-location-not-found)))
        (map-set location-stats location-id
            (merge stats {
                total-bookings: (+ (get total-bookings stats) u1),
                last-booking: stacks-block-height
            })))
    
    (update-user-bookings tx-sender booking-id total-cost)
    (update-owner-earnings (get owner location) owner-payment)
    
    (var-set total-platform-fees (+ (var-get total-platform-fees) platform-fee))
    (var-set booking-id-nonce (+ booking-id u1))
    (ok booking-id)))

(define-public (rate-location
    (location-id uint)
    (rating uint)
    (review (optional (string-utf8 200))))
  (let (
    (location (unwrap! (map-get? locations location-id) err-location-not-found))
    (stats (unwrap! (map-get? location-stats location-id) err-location-not-found)))
    
    (asserts! (<= rating u5) err-invalid-percentage)
    (asserts! (> rating u0) err-invalid-percentage)
    
    (map-set location-ratings 
        { location-id: location-id, rater: tx-sender }
        { rating: rating, review: review, rated-at: stacks-block-height })
    
    (let (
        (new-total-ratings (+ (get total-ratings stats) u1))
        (new-average (/ (+ (* (get average-rating stats) (get total-ratings stats)) rating) new-total-ratings)))
        (map-set location-stats location-id
            (merge stats { 
                average-rating: new-average,
                total-ratings: new-total-ratings
            })))
    (ok true)))

(define-public (update-location-price
    (location-id uint)
    (new-daily-rate uint))
  (let ((location (unwrap! (map-get? locations location-id) err-location-not-found)))
    (asserts! (is-eq tx-sender (get owner location)) err-not-authorized)
    (asserts! (> new-daily-rate u0) err-invalid-price)
    
    (map-set locations location-id
        (merge location { daily-rate: new-daily-rate }))
    (ok true)))

(define-public (toggle-location-status (location-id uint))
  (let ((location (unwrap! (map-get? locations location-id) err-location-not-found)))
    (asserts! (is-eq tx-sender (get owner location)) err-not-authorized)
    
    (map-set locations location-id
        (merge location { is-active: (not (get is-active location)) }))
    (ok true)))

(define-public (transfer-location
    (location-id uint)
    (new-owner principal))
  (let ((location (unwrap! (map-get? locations location-id) err-location-not-found)))
    (asserts! (is-eq tx-sender (get owner location)) err-not-authorized)
    
    (try! (nft-transfer? location-rights location-id tx-sender new-owner))
    
    (map-set locations location-id
        (merge location { owner: new-owner }))
    (ok true)))

(define-public (withdraw-platform-fees)
  (let ((fees (var-get total-platform-fees)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> fees u0) err-insufficient-balance)
    
    (try! (as-contract (stx-transfer? fees tx-sender contract-owner)))
    (var-set total-platform-fees u0)
    (ok fees)))

(define-public (create-discount
    (location-id uint)
    (discount-percentage uint)
    (valid-from uint)
    (valid-until uint)
    (min-bookings uint)
    (max-uses uint))
  (let (
    (location (unwrap! (map-get? locations location-id) err-location-not-found))
    (discount-id (var-get discount-id-nonce)))
    
    (asserts! (is-eq tx-sender (get owner location)) err-not-authorized)
    (asserts! (> discount-percentage u0) err-invalid-percentage)
    (asserts! (<= discount-percentage u100) err-invalid-percentage)
    (asserts! (> valid-until valid-from) err-invalid-dates)
    (asserts! (> max-uses u0) err-invalid-percentage)
    
    (map-set discounts discount-id {
        discount-id: discount-id,
        location-id: location-id,
        discount-percentage: discount-percentage,
        valid-from: valid-from,
        valid-until: valid-until,
        min-bookings: min-bookings,
        max-uses: max-uses,
        current-uses: u0,
        is-active: true,
        created-by: tx-sender
    })
    
    (var-set discount-id-nonce (+ discount-id u1))
    (ok discount-id)))

(define-public (toggle-discount (discount-id uint))
  (let ((discount (unwrap! (map-get? discounts discount-id) err-discount-not-found)))
    (asserts! (is-eq tx-sender (get created-by discount)) err-not-authorized)
    
    (map-set discounts discount-id
        (merge discount { is-active: (not (get is-active discount)) }))
    (ok true)))

(define-public (book-location-with-discount
    (location-id uint)
    (start-date uint)
    (end-date uint)
    (discount-id uint))
  (let (
    (location (unwrap! (map-get? locations location-id) err-location-not-found))
    (discount (unwrap! (map-get? discounts discount-id) err-discount-not-found))
    (booking-id (var-get booking-id-nonce))
    (duration (- end-date start-date))
    (base-cost (* (get daily-rate location) duration))
    (user-data (default-to { booking-ids: (list), total-spent: u0 } (map-get? user-bookings tx-sender)))
    (user-booking-count (len (get booking-ids user-data)))
    (discount-amount (/ (* base-cost (get discount-percentage discount)) u100))
    (discounted-cost (- base-cost discount-amount))
    (platform-fee (/ (* discounted-cost platform-fee-percentage) u100))
    (owner-payment (- discounted-cost platform-fee))
    (total-cost discounted-cost))
    
    (asserts! (is-eq (get location-id discount) location-id) err-discount-not-found)
    (asserts! (get is-active discount) err-discount-inactive)
    (asserts! (>= stacks-block-height (get valid-from discount)) err-discount-expired)
    (asserts! (<= stacks-block-height (get valid-until discount)) err-discount-expired)
    (asserts! (< (get current-uses discount) (get max-uses discount)) err-discount-expired)
    (asserts! (>= user-booking-count (get min-bookings discount)) err-min-bookings-not-met)
    
    (asserts! (get is-active location) err-listing-not-active)
    (asserts! (> end-date start-date) err-invalid-dates)
    (asserts! (>= duration min-booking-duration) err-invalid-dates)
    (asserts! (<= duration max-booking-duration) err-invalid-dates)
    (asserts! (default-to true (get is-available (map-get? location-availability { location-id: location-id, date: start-date }))) err-booking-conflict)
    
    (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
    (try! (as-contract (stx-transfer? owner-payment tx-sender (get owner location))))
    
    (map-set bookings booking-id {
        booking-id: booking-id,
        location-id: location-id,
        renter: tx-sender,
        start-date: start-date,
        end-date: end-date,
        daily-rate: (get daily-rate location),
        total-cost: total-cost,
        status: "confirmed",
        booked-at: stacks-block-height
    })
    
    (map-set location-availability 
        { location-id: location-id, date: start-date }
        { is-available: false, booking-id: (some booking-id) })
    
    (map-set locations location-id
        (merge location { 
            total-bookings: (+ (get total-bookings location) u1),
            total-earnings: (+ (get total-earnings location) owner-payment)
        }))
    
    (let ((stats (unwrap! (map-get? location-stats location-id) err-location-not-found)))
        (map-set location-stats location-id
            (merge stats {
                total-bookings: (+ (get total-bookings stats) u1),
                last-booking: stacks-block-height
            })))
    
    (map-set discounts discount-id
        (merge discount { current-uses: (+ (get current-uses discount) u1) }))
    
    (update-user-bookings tx-sender booking-id total-cost)
    (update-owner-earnings (get owner location) owner-payment)
    
    (var-set total-platform-fees (+ (var-get total-platform-fees) platform-fee))
    (var-set booking-id-nonce (+ booking-id u1))
    (ok booking-id)))



(define-private (update-user-bookings (user principal) (booking-id uint) (amount uint))
  (let ((user-data (default-to { booking-ids: (list), total-spent: u0 } 
                               (map-get? user-bookings user))))
    (map-set user-bookings user {
        booking-ids: (unwrap-panic (as-max-len? (append (get booking-ids user-data) booking-id) u100)),
        total-spent: (+ (get total-spent user-data) amount)
    })
    true))

(define-private (update-owner-earnings (owner principal) (amount uint))
  (let ((owner-data (unwrap-panic (map-get? owner-locations owner))))
    (map-set owner-locations owner
        (merge owner-data { total-earnings: (+ (get total-earnings owner-data) amount) }))
    true))

(define-read-only (get-location (location-id uint))
  (map-get? locations location-id))

(define-read-only (get-location-details (location-id uint))
  (map-get? location-details location-id))

(define-read-only (get-location-stats (location-id uint))
  (map-get? location-stats location-id))

(define-read-only (get-booking (booking-id uint))
  (map-get? bookings booking-id))

(define-read-only (get-user-bookings-data (user principal))
  (map-get? user-bookings user))

(define-read-only (get-owner-locations-data (owner principal))
  (map-get? owner-locations owner))

(define-read-only (get-location-rating (location-id uint) (rater principal))
  (map-get? location-ratings { location-id: location-id, rater: rater }))

(define-read-only (get-availability (location-id uint) (date uint))
  (default-to { is-available: true, booking-id: none } 
              (map-get? location-availability { location-id: location-id, date: date })))

(define-read-only (get-platform-fees)
  (ok (var-get total-platform-fees)))

(define-read-only (get-discount (discount-id uint))
  (map-get? discounts discount-id))

(define-read-only (get-active-discounts-for-location (location-id uint))
  (ok location-id))

;; title: Location-Rights-Tokenization
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

