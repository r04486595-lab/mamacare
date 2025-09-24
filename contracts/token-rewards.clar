;; title: token-rewards
;; version: 1.0.0
;; summary: MamaCare Token Rewards - MAMA token distribution and redemption system
;; description: Manages MAMA token minting, distribution, redemption, and gamification features for maternal health incentive program

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-unauthorized (err u202))
(define-constant err-insufficient-balance (err u203))
(define-constant err-invalid-amount (err u204))
(define-constant err-already-claimed (err u205))
(define-constant err-invalid-redemption (err u206))
(define-constant err-program-paused (err u207))
(define-constant err-invalid-tier (err u208))

;; Token economics constants
(define-constant mama-token-name "MamaCare")
(define-constant mama-token-symbol "MAMA")
(define-constant mama-token-decimals u6)
(define-constant mama-token-max-supply u100000000000000) ;; 100 million with 6 decimals

;; Reward tiers
(define-constant bronze-tier u1)
(define-constant silver-tier u2)
(define-constant gold-tier u3)
(define-constant platinum-tier u4)

;; Milestone rewards
(define-constant early-registration-reward u150)
(define-constant first-checkup-reward u100)
(define-constant monthly-consistency-reward u200)
(define-constant complete-program-reward u1000)
(define-constant referral-reward u100)
(define-constant education-session-reward u50)

;; Redemption rates (MAMA tokens per unit)
(define-constant healthcare-service-rate u50) ;; 50 MAMA per service unit
(define-constant medical-supply-rate u25) ;; 25 MAMA per supply unit
(define-constant cash-voucher-rate u100) ;; 100 MAMA per cash unit
(define-constant transportation-rate u20) ;; 20 MAMA per transport unit

;; data vars
(define-data-var total-supply uint u0)
(define-data-var total-distributed uint u0)
(define-data-var total-redeemed uint u0)
(define-data-var program-active bool true)
(define-data-var next-reward-id uint u1)
(define-data-var next-redemption-id uint u1)
(define-data-var reward-pool uint u0)

;; data maps

;; User token balances
(define-map token-balances
  { user: principal }
  { balance: uint, last-updated: uint }
)

;; User reward tiers and statistics
(define-map user-tiers
  { user: principal }
  {
    current-tier: uint,
    total-earned: uint,
    total-redeemed: uint,
    checkups-completed: uint,
    consistency-score: uint,
    tier-upgrade-date: uint,
    next-tier-requirements: uint
  }
)

;; Reward history for transparency
(define-map reward-history
  { reward-id: uint }
  {
    recipient: principal,
    amount: uint,
    reward-type: (string-ascii 32),
    source: (string-ascii 64),
    timestamp: uint,
    is-milestone: bool,
    patient-id: uint
  }
)

;; Redemption records
(define-map redemption-history
  { redemption-id: uint }
  {
    user: principal,
    amount: uint,
    redemption-type: (string-ascii 32),
    provider-info: (string-ascii 128),
    timestamp: uint,
    status: (string-ascii 16),
    verification-code: (string-ascii 32)
  }
)

;; Monthly leaderboard data
(define-map monthly-leaderboard
  { month: uint, rank: uint }
  {
    user: principal,
    tokens-earned: uint,
    checkups-completed: uint,
    consistency-percentage: uint
  }
)

;; Program milestones tracking
(define-map user-milestones
  { user: principal }
  {
    early-registration-claimed: bool,
    first-checkup-claimed: bool,
    monthly-streaks: uint,
    perfect-attendance-months: uint,
    referrals-made: uint,
    education-sessions: uint,
    total-milestone-tokens: uint
  }
)

;; Redemption provider registry
(define-map redemption-providers
  { provider-id: uint }
  {
    name: (string-ascii 64),
    service-type: (string-ascii 32),
    contact-info: (string-ascii 128),
    is-active: bool,
    total-redemptions: uint,
    rating: uint
  }
)

;; Community challenges and competitions
(define-map community-challenges
  { challenge-id: uint }
  {
    title: (string-ascii 64),
    description: (string-ascii 256),
    reward-pool: uint,
    start-date: uint,
    end-date: uint,
    is-active: bool,
    participants: uint,
    winners-count: uint
  }
)

;; Challenge participation
(define-map challenge-participants
  { challenge-id: uint, user: principal }
  {
    progress-score: uint,
    completion-status: bool,
    reward-earned: uint
  }
)

;; public functions

;; Mint tokens for checkup rewards
(define-public (mint-checkup-reward (recipient principal) (amount uint) (patient-id uint) (checkup-type (string-ascii 32)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (var-get program-active) err-program-paused)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (< (+ (var-get total-supply) amount) mama-token-max-supply) err-invalid-amount)
    
    (let (
      (reward-id (var-get next-reward-id))
      (current-height burn-block-height)
      (current-balance (get balance (default-to { balance: u0, last-updated: u0 } (map-get? token-balances { user: recipient }))))
    )
      ;; Update user balance
      (map-set token-balances
        { user: recipient }
        { balance: (+ current-balance amount), last-updated: current-height })
      
      ;; Record reward history
      (map-set reward-history
        { reward-id: reward-id }
        {
          recipient: recipient,
          amount: amount,
          reward-type: checkup-type,
          source: "checkup-completion",
          timestamp: current-height,
          is-milestone: false,
          patient-id: patient-id
        })
      
      ;; Update user tier information
      (unwrap! (update-user-tier recipient amount) err-invalid-amount)
      
      ;; Update global statistics
      (var-set total-supply (+ (var-get total-supply) amount))
      (var-set total-distributed (+ (var-get total-distributed) amount))
      (var-set next-reward-id (+ reward-id u1))
      
      (ok reward-id)
    )
  )
)

;; Mint milestone rewards
(define-public (mint-milestone-reward (recipient principal) (milestone-type (string-ascii 32)) (patient-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (var-get program-active) err-program-paused)
    
    (let (
      (milestone-info (default-to 
                       {
                         early-registration-claimed: false,
                         first-checkup-claimed: false,
                         monthly-streaks: u0,
                         perfect-attendance-months: u0,
                         referrals-made: u0,
                         education-sessions: u0,
                         total-milestone-tokens: u0
                       }
                       (map-get? user-milestones { user: recipient })))
      (reward-amount (get-milestone-reward-amount milestone-type))
      (current-height burn-block-height)
    )
      (asserts! (> reward-amount u0) err-invalid-amount)
      (asserts! (not (is-milestone-already-claimed recipient milestone-type milestone-info)) err-already-claimed)
      
      ;; Mint tokens
      (unwrap! (mint-tokens-internal recipient reward-amount milestone-type patient-id true) err-invalid-amount)
      
      ;; Update milestone tracking
      (map-set user-milestones
        { user: recipient }
        (merge milestone-info (update-milestone-status milestone-type milestone-info reward-amount)))
      
      (ok reward-amount)
    )
  )
)

;; Redeem tokens for services
(define-public (redeem-tokens (amount uint) (redemption-type (string-ascii 32)) (provider-info (string-ascii 128)))
  (let (
    (user-balance (get balance (default-to { balance: u0, last-updated: u0 } (map-get? token-balances { user: tx-sender }))))
    (redemption-id (var-get next-redemption-id))
    (current-height burn-block-height)
    (verification-code (generate-verification-code redemption-id))
  )
    (asserts! (var-get program-active) err-program-paused)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= user-balance amount) err-insufficient-balance)
    (asserts! (is-valid-redemption-type redemption-type) err-invalid-redemption)
    
    ;; Deduct tokens from user balance
    (map-set token-balances
      { user: tx-sender }
      { balance: (- user-balance amount), last-updated: current-height })
    
    ;; Record redemption
    (map-set redemption-history
      { redemption-id: redemption-id }
      {
        user: tx-sender,
        amount: amount,
        redemption-type: redemption-type,
        provider-info: provider-info,
        timestamp: current-height,
        status: "pending",
        verification-code: verification-code
      })
    
    ;; Update user tier
    (try! (update-user-redemption-stats tx-sender amount))
    
    ;; Update global statistics
    (var-set total-redeemed (+ (var-get total-redeemed) amount))
    (var-set next-redemption-id (+ redemption-id u1))
    
    (ok { redemption-id: redemption-id, verification-code: verification-code })
  )
)

;; Create community challenge
(define-public (create-challenge 
  (title (string-ascii 64)) 
  (description (string-ascii 256)) 
  (challenge-reward-pool uint) 
  (duration-days uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> challenge-reward-pool u0) err-invalid-amount)
    
    (let (
      (challenge-id (var-get next-reward-id))
      (current-height burn-block-height)
      (end-date (+ current-height (* duration-days u144))) ;; Approximate blocks per day
    )
      (map-set community-challenges
        { challenge-id: challenge-id }
        {
          title: title,
          description: description,
          reward-pool: challenge-reward-pool,
          start-date: current-height,
          end-date: end-date,
          is-active: true,
          participants: u0,
          winners-count: u0
        })
      
      (var-set reward-pool (+ (var-get reward-pool) challenge-reward-pool))
      (ok challenge-id)
    )
  )
)

;; Join community challenge
(define-public (join-challenge (challenge-id uint))
  (let ((challenge-info (unwrap! (map-get? community-challenges { challenge-id: challenge-id }) err-not-found)))
    (asserts! (get is-active challenge-info) err-invalid-redemption)
    (asserts! (< burn-block-height (get end-date challenge-info)) err-invalid-redemption)
    (asserts! (is-none (map-get? challenge-participants { challenge-id: challenge-id, user: tx-sender })) err-already-claimed)
    
    ;; Add participant
    (map-set challenge-participants
      { challenge-id: challenge-id, user: tx-sender }
      {
        progress-score: u0,
        completion-status: false,
        reward-earned: u0
      })
    
    ;; Update challenge participant count
    (map-set community-challenges
      { challenge-id: challenge-id }
      (merge challenge-info { participants: (+ (get participants challenge-info) u1) }))
    
    (ok true)
  )
)

;; Transfer tokens between users
(define-public (transfer-tokens (recipient principal) (amount uint))
  (let (
    (sender-balance (get balance (default-to { balance: u0, last-updated: u0 } (map-get? token-balances { user: tx-sender }))))
    (recipient-balance (get balance (default-to { balance: u0, last-updated: u0 } (map-get? token-balances { user: recipient }))))
    (current-height burn-block-height)
  )
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= sender-balance amount) err-insufficient-balance)
    
    ;; Update sender balance
    (map-set token-balances
      { user: tx-sender }
      { balance: (- sender-balance amount), last-updated: current-height })
    
    ;; Update recipient balance
    (map-set token-balances
      { user: recipient }
      { balance: (+ recipient-balance amount), last-updated: current-height })
    
    (ok true)
  )
)

;; Admin functions
(define-public (update-redemption-status (redemption-id uint) (new-status (string-ascii 16)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (let ((redemption-info (unwrap! (map-get? redemption-history { redemption-id: redemption-id }) err-not-found)))
      (map-set redemption-history
        { redemption-id: redemption-id }
        (merge redemption-info { status: new-status }))
      (ok true)
    )
  )
)

(define-public (pause-program)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set program-active false)
    (ok true)
  )
)

(define-public (resume-program)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set program-active true)
    (ok true)
  )
)

;; read only functions

(define-read-only (get-token-balance (user principal))
  (get balance (default-to { balance: u0, last-updated: u0 } (map-get? token-balances { user: user })))
)

(define-read-only (get-user-tier (user principal))
  (map-get? user-tiers { user: user })
)

(define-read-only (get-reward-history (reward-id uint))
  (map-get? reward-history { reward-id: reward-id })
)

(define-read-only (get-redemption-info (redemption-id uint))
  (map-get? redemption-history { redemption-id: redemption-id })
)

(define-read-only (get-user-milestones (user principal))
  (map-get? user-milestones { user: user })
)

(define-read-only (get-challenge-info (challenge-id uint))
  (map-get? community-challenges { challenge-id: challenge-id })
)

(define-read-only (get-challenge-participation (challenge-id uint) (user principal))
  (map-get? challenge-participants { challenge-id: challenge-id, user: user })
)

(define-read-only (get-program-stats)
  {
    total-supply: (var-get total-supply),
    total-distributed: (var-get total-distributed),
    total-redeemed: (var-get total-redeemed),
    program-active: (var-get program-active),
    reward-pool: (var-get reward-pool),
    next-reward-id: (var-get next-reward-id)
  }
)

(define-read-only (get-leaderboard (month uint))
  (list 
    (map-get? monthly-leaderboard { month: month, rank: u1 })
    (map-get? monthly-leaderboard { month: month, rank: u2 })
    (map-get? monthly-leaderboard { month: month, rank: u3 })
    (map-get? monthly-leaderboard { month: month, rank: u4 })
    (map-get? monthly-leaderboard { month: month, rank: u5 })
  )
)

;; private functions

(define-private (mint-tokens-internal (recipient principal) (amount uint) (reward-type (string-ascii 32)) (patient-id uint) (is-milestone bool))
  (let (
    (reward-id (var-get next-reward-id))
    (current-height burn-block-height)
    (current-balance (get balance (default-to { balance: u0, last-updated: u0 } (map-get? token-balances { user: recipient }))))
  )
    ;; Update user balance
    (map-set token-balances
      { user: recipient }
      { balance: (+ current-balance amount), last-updated: current-height })
    
    ;; Record reward history
    (map-set reward-history
      { reward-id: reward-id }
      {
        recipient: recipient,
        amount: amount,
        reward-type: reward-type,
        source: (if is-milestone "milestone-achievement" "checkup-completion"),
        timestamp: current-height,
        is-milestone: is-milestone,
        patient-id: patient-id
      })
    
    ;; Update global statistics
    (var-set total-supply (+ (var-get total-supply) amount))
    (var-set total-distributed (+ (var-get total-distributed) amount))
    (var-set next-reward-id (+ reward-id u1))
    
    (ok reward-id)
  )
)

(define-private (update-user-tier (user principal) (tokens-earned uint))
  (let (
    (current-tier-info (default-to 
                        {
                          current-tier: bronze-tier,
                          total-earned: u0,
                          total-redeemed: u0,
                          checkups-completed: u0,
                          consistency-score: u0,
                          tier-upgrade-date: u0,
                          next-tier-requirements: u500
                        }
                        (map-get? user-tiers { user: user })))
    (new-total-earned (+ (get total-earned current-tier-info) tokens-earned))
    (new-tier (calculate-tier new-total-earned))
    (current-height burn-block-height)
  )
    (map-set user-tiers
      { user: user }
      (merge current-tier-info {
        total-earned: new-total-earned,
        checkups-completed: (+ (get checkups-completed current-tier-info) u1),
        current-tier: new-tier,
        tier-upgrade-date: (if (> new-tier (get current-tier current-tier-info)) current-height (get tier-upgrade-date current-tier-info)),
        next-tier-requirements: (get-tier-requirements new-tier)
      }))
    
    (ok true)
  )
)

(define-private (update-user-redemption-stats (user principal) (redeemed-amount uint))
  (let (
    (current-tier-info (unwrap! (map-get? user-tiers { user: user }) err-not-found))
  )
    (map-set user-tiers
      { user: user }
      (merge current-tier-info { total-redeemed: (+ (get total-redeemed current-tier-info) redeemed-amount) }))
    
    (ok true)
  )
)

(define-private (get-milestone-reward-amount (milestone-type (string-ascii 32)))
  (if (is-eq milestone-type "early-registration")
    early-registration-reward
    (if (is-eq milestone-type "first-checkup")
      first-checkup-reward
      (if (is-eq milestone-type "monthly-consistency")
        monthly-consistency-reward
        (if (is-eq milestone-type "complete-program")
          complete-program-reward
          (if (is-eq milestone-type "referral")
            referral-reward
            (if (is-eq milestone-type "education")
              education-session-reward
              u0))))))
)

(define-private (is-milestone-already-claimed (user principal) (milestone-type (string-ascii 32)) (milestone-info (tuple (early-registration-claimed bool) (first-checkup-claimed bool) (monthly-streaks uint) (perfect-attendance-months uint) (referrals-made uint) (education-sessions uint) (total-milestone-tokens uint))))
  (if (is-eq milestone-type "early-registration")
    (get early-registration-claimed milestone-info)
    (if (is-eq milestone-type "first-checkup")
      (get first-checkup-claimed milestone-info)
      false))
)

(define-private (update-milestone-status (milestone-type (string-ascii 32)) (milestone-info (tuple (early-registration-claimed bool) (first-checkup-claimed bool) (monthly-streaks uint) (perfect-attendance-months uint) (referrals-made uint) (education-sessions uint) (total-milestone-tokens uint))) (reward-amount uint))
  (if (is-eq milestone-type "early-registration")
    (merge milestone-info { early-registration-claimed: true, total-milestone-tokens: (+ (get total-milestone-tokens milestone-info) reward-amount) })
    (if (is-eq milestone-type "first-checkup")
      (merge milestone-info { first-checkup-claimed: true, total-milestone-tokens: (+ (get total-milestone-tokens milestone-info) reward-amount) })
      (if (is-eq milestone-type "referral")
        (merge milestone-info { referrals-made: (+ (get referrals-made milestone-info) u1), total-milestone-tokens: (+ (get total-milestone-tokens milestone-info) reward-amount) })
        (if (is-eq milestone-type "education")
          (merge milestone-info { education-sessions: (+ (get education-sessions milestone-info) u1), total-milestone-tokens: (+ (get total-milestone-tokens milestone-info) reward-amount) })
          (merge milestone-info { total-milestone-tokens: (+ (get total-milestone-tokens milestone-info) reward-amount) })))))
)

(define-private (calculate-tier (total-earned uint))
  (if (>= total-earned u5000)
    platinum-tier
    (if (>= total-earned u2000)
      gold-tier
      (if (>= total-earned u500)
        silver-tier
        bronze-tier)))
)

(define-private (get-tier-requirements (tier uint))
  (if (is-eq tier bronze-tier)
    u500
    (if (is-eq tier silver-tier)
      u2000
      (if (is-eq tier gold-tier)
        u5000
        u10000)))
)

(define-private (is-valid-redemption-type (redemption-type (string-ascii 32)))
  (or (is-eq redemption-type "healthcare")
      (is-eq redemption-type "supplies")
      (is-eq redemption-type "cash")
      (is-eq redemption-type "transport"))
)

(define-private (generate-verification-code (redemption-id uint))
  ;; Simple verification code generation (in production, would be more sophisticated)
  "VERIFY"
)
