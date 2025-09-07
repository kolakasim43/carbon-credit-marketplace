;; Carbon Credit Marketplace Smart Contract
;; A comprehensive platform for verified carbon offset tokenization, trading, and compliance tracking

;; =============================================================================
;; CONSTANTS
;; =============================================================================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1001))
(define-constant ERR-INVALID-AMOUNT (err u1002))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1003))
(define-constant ERR-PROJECT-NOT-FOUND (err u1004))
(define-constant ERR-PROJECT-NOT-VERIFIED (err u1005))
(define-constant ERR-ORDER-NOT-FOUND (err u1006))
(define-constant ERR-INVALID-PRICE (err u1007))
(define-constant ERR-TRADE-MISMATCH (err u1008))
(define-constant ERR-ALREADY-EXISTS (err u1009))
(define-constant ERR-INVALID-CALLER (err u1010))

;; Contract roles
(define-constant ROLE-ADMIN u100)
(define-constant ROLE-ISSUER u200)
(define-constant ROLE-VERIFIER u300)
(define-constant ROLE-TRADER u400)

;; Project status constants
(define-constant STATUS-PENDING u1)
(define-constant STATUS-VERIFIED u2)
(define-constant STATUS-REJECTED u3)

;; Order types
(define-constant ORDER-SELL u1)
(define-constant ORDER-BUY u2)

;; Maximum values
(define-constant MAX-SUPPLY u1000000000000) ;; 1 trillion credits max
(define-constant MIN-ORDER-AMOUNT u1)

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

;; Contract owner and admin controls
(define-data-var contract-owner principal tx-sender)
(define-data-var total-supply uint u0)
(define-data-var next-project-id uint u1)
(define-data-var next-order-id uint u1)
(define-data-var marketplace-fee uint u50) ;; 0.5% fee in basis points

;; =============================================================================
;; DATA MAPS
;; =============================================================================

;; Carbon credit balances (SIP-010 compatible)
(define-map balances principal uint)

;; User roles and permissions
(define-map user-roles principal uint)

;; Carbon offset projects registry
(define-map projects 
    uint 
    {
        name: (string-ascii 100),
        description: (string-ascii 500),
        location: (string-ascii 100),
        project-type: (string-ascii 50),
        carbon-offset-amount: uint,
        verification-status: uint,
        issuer: principal,
        verifier: (optional principal),
        created-at: uint,
        verified-at: (optional uint)
    }
)

;; Trading orders (marketplace functionality)
(define-map orders 
    uint 
    {
        trader: principal,
        order-type: uint,
        amount: uint,
        price-per-credit: uint,
        created-at: uint,
        is-active: bool
    }
)

;; Corporate compliance tracking
(define-map corporate-profiles 
    principal 
    {
        company-name: (string-ascii 100),
        offset-target: uint,
        offset-achieved: uint,
        compliance-deadline: uint,
        registered-at: uint
    }
)

;; Trade history for audit trails
(define-map trade-history 
    uint 
    {
        seller: principal,
        buyer: principal,
        amount: uint,
        price-per-credit: uint,
        trade-timestamp: uint,
        project-id: uint
    }
)

;; Project verification votes (multi-party verification)
(define-map verification-votes 
    {project-id: uint, verifier: principal} 
    {vote: bool, voted-at: uint}
)

;; =============================================================================
;; PRIVATE FUNCTIONS
;; =============================================================================

;; Check if caller has required role
(define-private (has-role (user principal) (required-role uint))
    (let ((user-role (default-to u0 (map-get? user-roles user))))
        (or 
            (is-eq user (var-get contract-owner))
            (>= user-role required-role)
        )
    )
)

;; Calculate trading fee
(define-private (calculate-fee (amount uint))
    (/ (* amount (var-get marketplace-fee)) u10000)
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

;; Get carbon credit balance for an account
(define-read-only (get-balance (account principal))
    (default-to u0 (map-get? balances account))
)

;; Get total supply of carbon credits
(define-read-only (get-total-supply)
    (var-get total-supply)
)

;; Get project details
(define-read-only (get-project-details (project-id uint))
    (map-get? projects project-id)
)

;; Get order details
(define-read-only (get-order-details (order-id uint))
    (map-get? orders order-id)
)

;; Get corporate compliance status
(define-read-only (get-compliance-status (company principal))
    (map-get? corporate-profiles company)
)

;; Check if project is verified
(define-read-only (is-project-verified (project-id uint))
    (let ((project (map-get? projects project-id)))
        (match project
            project-data (is-eq (get verification-status project-data) STATUS-VERIFIED)
            false
        )
    )
)

;; Get user role
(define-read-only (get-user-role (user principal))
    (default-to u0 (map-get? user-roles user))
)

;; Get marketplace fee
(define-read-only (get-marketplace-fee)
    (var-get marketplace-fee)
)

;; =============================================================================
;; PUBLIC FUNCTIONS - ADMIN
;; =============================================================================

;; Set user role (admin only)
(define-public (set-user-role (user principal) (role uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (map-set user-roles user role))
    )
)

;; Update marketplace fee (admin only)
(define-public (set-marketplace-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-fee u1000) ERR-INVALID-AMOUNT) ;; Max 10% fee
        (ok (var-set marketplace-fee new-fee))
    )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - PROJECT MANAGEMENT
;; =============================================================================

;; Register a new carbon offset project
(define-public (register-project 
    (name (string-ascii 100))
    (description (string-ascii 500))
    (location (string-ascii 100))
    (project-type (string-ascii 50))
    (carbon-offset-amount uint)
)
    (let 
        (
            (project-id (var-get next-project-id))
            (current-height stacks-block-height)
        )
        (begin
            (asserts! (has-role tx-sender ROLE-ISSUER) ERR-NOT-AUTHORIZED)
            (asserts! (> carbon-offset-amount u0) ERR-INVALID-AMOUNT)
            
            ;; Store project data
            (map-set projects project-id {
                name: name,
                description: description,
                location: location,
                project-type: project-type,
                carbon-offset-amount: carbon-offset-amount,
                verification-status: STATUS-PENDING,
                issuer: tx-sender,
                verifier: none,
                created-at: current-height,
                verified-at: none
            })
            
            ;; Increment next project ID
            (var-set next-project-id (+ project-id u1))
            (ok project-id)
        )
    )
)

;; Verify a project (verifier only)
(define-public (verify-project (project-id uint))
    (let ((project (unwrap! (map-get? projects project-id) ERR-PROJECT-NOT-FOUND)))
        (begin
            (asserts! (has-role tx-sender ROLE-VERIFIER) ERR-NOT-AUTHORIZED)
            (asserts! (is-eq (get verification-status project) STATUS-PENDING) ERR-ALREADY-EXISTS)
            
            ;; Update project verification status
            (map-set projects project-id (merge project {
                verification-status: STATUS-VERIFIED,
                verifier: (some tx-sender),
                verified-at: (some stacks-block-height)
            }))
            
            (ok true)
        )
    )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - CREDIT MANAGEMENT
;; =============================================================================

;; Issue carbon credits for a verified project (issuer only)
(define-public (issue-credits (project-id uint) (amount uint) (recipient principal))
    (let ((project (unwrap! (map-get? projects project-id) ERR-PROJECT-NOT-FOUND)))
        (begin
            (asserts! (has-role tx-sender ROLE-ISSUER) ERR-NOT-AUTHORIZED)
            (asserts! (is-project-verified project-id) ERR-PROJECT-NOT-VERIFIED)
            (asserts! (> amount u0) ERR-INVALID-AMOUNT)
            (asserts! (<= (+ (var-get total-supply) amount) MAX-SUPPLY) ERR-INVALID-AMOUNT)
            
            ;; Update recipient balance
            (let ((current-balance (get-balance recipient)))
                (map-set balances recipient (+ current-balance amount))
            )
            
            ;; Update total supply
            (var-set total-supply (+ (var-get total-supply) amount))
            
            (ok amount)
        )
    )
)

;; Transfer carbon credits between accounts
(define-public (transfer-credits (amount uint) (recipient principal))
    (let 
        (
            (sender-balance (get-balance tx-sender))
            (recipient-balance (get-balance recipient))
        )
        (begin
            (asserts! (> amount u0) ERR-INVALID-AMOUNT)
            (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
            
            ;; Update balances
            (map-set balances tx-sender (- sender-balance amount))
            (map-set balances recipient (+ recipient-balance amount))
            
            (ok true)
        )
    )
)

;; Burn/retire carbon credits (permanent retirement)
(define-public (burn-credits (amount uint))
    (let ((sender-balance (get-balance tx-sender)))
        (begin
            (asserts! (> amount u0) ERR-INVALID-AMOUNT)
            (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
            
            ;; Update sender balance and total supply
            (map-set balances tx-sender (- sender-balance amount))
            (var-set total-supply (- (var-get total-supply) amount))
            
            (ok amount)
        )
    )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - TRADING
;; =============================================================================

;; Create a sell order
(define-public (create-sell-order (amount uint) (price-per-credit uint))
    (let ((order-id (var-get next-order-id)))
        (begin
            (asserts! (> amount MIN-ORDER-AMOUNT) ERR-INVALID-AMOUNT)
            (asserts! (> price-per-credit u0) ERR-INVALID-PRICE)
            (asserts! (>= (get-balance tx-sender) amount) ERR-INSUFFICIENT-BALANCE)
            
            ;; Create sell order
            (map-set orders order-id {
                trader: tx-sender,
                order-type: ORDER-SELL,
                amount: amount,
                price-per-credit: price-per-credit,
                created-at: stacks-block-height,
                is-active: true
            })
            
            (var-set next-order-id (+ order-id u1))
            (ok order-id)
        )
    )
)

;; Create a buy order
(define-public (create-buy-order (amount uint) (price-per-credit uint))
    (let ((order-id (var-get next-order-id)))
        (begin
            (asserts! (> amount MIN-ORDER-AMOUNT) ERR-INVALID-AMOUNT)
            (asserts! (> price-per-credit u0) ERR-INVALID-PRICE)
            
            ;; Create buy order
            (map-set orders order-id {
                trader: tx-sender,
                order-type: ORDER-BUY,
                amount: amount,
                price-per-credit: price-per-credit,
                created-at: stacks-block-height,
                is-active: true
            })
            
            (var-set next-order-id (+ order-id u1))
            (ok order-id)
        )
    )
)

;; Execute a trade between matching orders
(define-public (execute-trade (sell-order-id uint) (buy-order-id uint) (trade-amount uint))
    (let 
        (
            (sell-order (unwrap! (map-get? orders sell-order-id) ERR-ORDER-NOT-FOUND))
            (buy-order (unwrap! (map-get? orders buy-order-id) ERR-ORDER-NOT-FOUND))
            (seller (get trader sell-order))
            (buyer (get trader buy-order))
            (sell-price (get price-per-credit sell-order))
            (buy-price (get price-per-credit buy-order))
        )
        (begin
            ;; Validate trade conditions
            (asserts! (get is-active sell-order) ERR-ORDER-NOT-FOUND)
            (asserts! (get is-active buy-order) ERR-ORDER-NOT-FOUND)
            (asserts! (is-eq (get order-type sell-order) ORDER-SELL) ERR-TRADE-MISMATCH)
            (asserts! (is-eq (get order-type buy-order) ORDER-BUY) ERR-TRADE-MISMATCH)
            (asserts! (>= buy-price sell-price) ERR-TRADE-MISMATCH)
            (asserts! (<= trade-amount (get amount sell-order)) ERR-INVALID-AMOUNT)
            (asserts! (<= trade-amount (get amount buy-order)) ERR-INVALID-AMOUNT)
            (asserts! (>= (get-balance seller) trade-amount) ERR-INSUFFICIENT-BALANCE)
            
            ;; Execute the trade - transfer credits from seller to buyer
            (let 
                (
                    (seller-balance (get-balance seller))
                    (buyer-balance (get-balance buyer))
                )
                (map-set balances seller (- seller-balance trade-amount))
                (map-set balances buyer (+ buyer-balance trade-amount))
            )
            
            ;; Update order amounts
            (let 
                (
                    (remaining-sell (- (get amount sell-order) trade-amount))
                    (remaining-buy (- (get amount buy-order) trade-amount))
                )
                (if (is-eq remaining-sell u0)
                    (map-set orders sell-order-id (merge sell-order {is-active: false}))
                    (map-set orders sell-order-id (merge sell-order {amount: remaining-sell}))
                )
                (if (is-eq remaining-buy u0)
                    (map-set orders buy-order-id (merge buy-order {is-active: false}))
                    (map-set orders buy-order-id (merge buy-order {amount: remaining-buy}))
                )
            )
            
            (ok {seller: seller, buyer: buyer, amount: trade-amount, price: sell-price})
        )
    )
)

;; Cancel an order
(define-public (cancel-order (order-id uint))
    (let ((order (unwrap! (map-get? orders order-id) ERR-ORDER-NOT-FOUND)))
        (begin
            (asserts! (is-eq tx-sender (get trader order)) ERR-NOT-AUTHORIZED)
            (asserts! (get is-active order) ERR-ORDER-NOT-FOUND)
            
            ;; Deactivate the order
            (map-set orders order-id (merge order {is-active: false}))
            (ok true)
        )
    )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - CORPORATE COMPLIANCE
;; =============================================================================

;; Register corporate profile for compliance tracking
(define-public (register-corporate-profile 
    (company-name (string-ascii 100))
    (offset-target uint)
    (compliance-deadline uint)
)
    (begin
        (asserts! (> offset-target u0) ERR-INVALID-AMOUNT)
        (asserts! (> compliance-deadline stacks-block-height) ERR-INVALID-AMOUNT)
        
        (map-set corporate-profiles tx-sender {
            company-name: company-name,
            offset-target: offset-target,
            offset-achieved: u0,
            compliance-deadline: compliance-deadline,
            registered-at: stacks-block-height
        })
        
        (ok true)
    )
)

;; Track corporate carbon offsetting (when credits are burned for compliance)
(define-public (track-corporate-offset (amount uint))
    (let ((profile (unwrap! (map-get? corporate-profiles tx-sender) ERR-PROJECT-NOT-FOUND)))
        (begin
            (asserts! (> amount u0) ERR-INVALID-AMOUNT)
            
            ;; Burn the credits for permanent retirement
            (try! (burn-credits amount))
            
            ;; Update offset achieved
            (map-set corporate-profiles tx-sender (merge profile {
                offset-achieved: (+ (get offset-achieved profile) amount)
            }))
            
            (ok amount)
        )
    )
)

;; Check if corporate compliance target is met
(define-read-only (is-compliance-target-met (company principal))
    (let ((profile (map-get? corporate-profiles company)))
        (match profile
            profile-data (>= (get offset-achieved profile-data) (get offset-target profile-data))
            false
        )
    )
)
