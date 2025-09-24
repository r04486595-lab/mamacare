;; title: health-records
;; version: 1.0.0
;; summary: MamaCare Health Records - Maternal health tracking system
;; description: Manages patient registration, provider verification, checkup records, and health milestones for maternal care incentive program

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-data (err u104))
(define-constant err-not-verified (err u105))
(define-constant err-invalid-stage (err u106))
(define-constant err-checkup-exists (err u107))
(define-constant err-invalid-provider (err u108))

;; Pregnancy stages
(define-constant first-trimester u1)
(define-constant second-trimester u2)
(define-constant third-trimester u3)
(define-constant postpartum u4)

;; Token rewards per checkup
(define-constant first-trimester-reward u50)
(define-constant second-trimester-reward u75)
(define-constant third-trimester-reward u100)
(define-constant screening-bonus u25)
(define-constant education-bonus u20)

;; data vars
(define-data-var next-patient-id uint u1)
(define-data-var next-provider-id uint u1)
(define-data-var next-checkup-id uint u1)
(define-data-var total-patients uint u0)
(define-data-var total-providers uint u0)
(define-data-var total-checkups uint u0)
(define-data-var program-active bool true)

;; data maps

;; Patient registry with health information
(define-map patients
  { patient-id: uint }
  {
    wallet: principal,
    name: (string-ascii 64),
    age: uint,
    registration-date: uint,
    expected-due-date: uint,
    current-stage: uint,
    total-checkups: uint,
    health-score: uint,
    is-active: bool,
    provider-id: uint,
    risk-level: (string-ascii 16)
  }
)

;; Patient lookup by wallet address
(define-map patient-wallets
  { wallet: principal }
  { patient-id: uint }
)

;; Healthcare provider registry
(define-map providers
  { provider-id: uint }
  {
    wallet: principal,
    name: (string-ascii 64),
    license-number: (string-ascii 32),
    facility-name: (string-ascii 64),
    registration-date: uint,
    is-verified: bool,
    total-patients: uint,
    total-checkups-verified: uint,
    rating: uint
  }
)

;; Provider lookup by wallet address
(define-map provider-wallets
  { wallet: principal }
  { provider-id: uint }
)

;; Individual checkup records
(define-map checkups
  { checkup-id: uint }
  {
    patient-id: uint,
    provider-id: uint,
    checkup-date: uint,
    pregnancy-stage: uint,
    week-of-pregnancy: uint,
    checkup-type: (string-ascii 32),
    vital-signs-normal: bool,
    screenings-completed: (list 5 (string-ascii 32)),
    notes: (string-ascii 256),
    rewards-earned: uint,
    is-verified: bool
  }
)

;; Patient checkup history
(define-map patient-checkups
  { patient-id: uint, checkup-date: uint }
  { checkup-id: uint }
)

;; Milestone tracking for incentive programs
(define-map patient-milestones
  { patient-id: uint }
  {
    first-visit-completed: bool,
    early-registration-bonus: bool,
    consistent-attendance: uint,
    all-screenings-completed: bool,
    education-sessions-attended: uint,
    referral-count: uint,
    total-milestone-rewards: uint
  }
)

;; Provider performance tracking
(define-map provider-stats
  { provider-id: uint }
  {
    monthly-checkups: uint,
    patient-satisfaction: uint,
    compliance-rate: uint,
    last-activity: uint,
    performance-score: uint
  }
)

;; public functions

;; Register new patient in the system
(define-public (register-patient 
  (name (string-ascii 64)) 
  (age uint) 
  (expected-due-date uint) 
  (provider-id uint)
  (risk-level (string-ascii 16)))
  (let 
    (
      (patient-id (var-get next-patient-id))
      (current-height burn-block-height)
    )
    (asserts! (var-get program-active) err-invalid-data)
    (asserts! (and (>= age u16) (<= age u50)) err-invalid-data)
    (asserts! (> expected-due-date current-height) err-invalid-data)
    (asserts! (is-none (map-get? patient-wallets { wallet: tx-sender })) err-already-exists)
    
    ;; Verify provider exists and is verified
    (let ((provider-info (unwrap! (map-get? providers { provider-id: provider-id }) err-not-found)))
      (asserts! (get is-verified provider-info) err-not-verified)
      
      ;; Register patient
      (map-set patients
        { patient-id: patient-id }
        {
          wallet: tx-sender,
          name: name,
          age: age,
          registration-date: current-height,
          expected-due-date: expected-due-date,
          current-stage: first-trimester,
          total-checkups: u0,
          health-score: u100,
          is-active: true,
          provider-id: provider-id,
          risk-level: risk-level
        })
      
      ;; Create wallet lookup
      (map-set patient-wallets
        { wallet: tx-sender }
        { patient-id: patient-id })
      
      ;; Initialize milestones
      (map-set patient-milestones
        { patient-id: patient-id }
        {
          first-visit-completed: false,
          early-registration-bonus: (< current-height (- expected-due-date u1008)), ;; ~7 days before due date
          consistent-attendance: u0,
          all-screenings-completed: false,
          education-sessions-attended: u0,
          referral-count: u0,
          total-milestone-rewards: u0
        })
      
      ;; Update provider patient count
      (map-set providers
        { provider-id: provider-id }
        (merge provider-info { total-patients: (+ (get total-patients provider-info) u1) }))
      
      ;; Update global counters
      (var-set next-patient-id (+ patient-id u1))
      (var-set total-patients (+ (var-get total-patients) u1))
      
      (ok patient-id)
    )
  )
)

;; Register healthcare provider
(define-public (register-provider 
  (name (string-ascii 64)) 
  (license-number (string-ascii 32)) 
  (facility-name (string-ascii 64)))
  (let 
    (
      (provider-id (var-get next-provider-id))
      (current-height burn-block-height)
    )
    (asserts! (is-none (map-get? provider-wallets { wallet: tx-sender })) err-already-exists)
    (asserts! (> (len name) u0) err-invalid-data)
    (asserts! (> (len license-number) u0) err-invalid-data)
    
    ;; Register provider (pending verification)
    (map-set providers
      { provider-id: provider-id }
      {
        wallet: tx-sender,
        name: name,
        license-number: license-number,
        facility-name: facility-name,
        registration-date: current-height,
        is-verified: false,
        total-patients: u0,
        total-checkups-verified: u0,
        rating: u50
      })
    
    ;; Create wallet lookup
    (map-set provider-wallets
      { wallet: tx-sender }
      { provider-id: provider-id })
    
    ;; Initialize stats
    (map-set provider-stats
      { provider-id: provider-id }
      {
        monthly-checkups: u0,
        patient-satisfaction: u50,
        compliance-rate: u100,
        last-activity: current-height,
        performance-score: u50
      })
    
    ;; Update global counters
    (var-set next-provider-id (+ provider-id u1))
    (var-set total-providers (+ (var-get total-providers) u1))
    
    (ok provider-id)
  )
)

;; Verify provider (admin only)
(define-public (verify-provider (provider-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (let ((provider-info (unwrap! (map-get? providers { provider-id: provider-id }) err-not-found)))
      (map-set providers
        { provider-id: provider-id }
        (merge provider-info { is-verified: true, rating: u75 }))
      (ok true)
    )
  )
)

;; Record completed checkup
(define-public (record-checkup 
  (patient-id uint) 
  (pregnancy-stage uint)
  (week-of-pregnancy uint)
  (checkup-type (string-ascii 32))
  (vital-signs-normal bool)
  (screenings-completed (list 5 (string-ascii 32)))
  (notes (string-ascii 256)))
  (let 
    (
      (checkup-id (var-get next-checkup-id))
      (current-height burn-block-height)
      (provider-lookup (unwrap! (map-get? provider-wallets { wallet: tx-sender }) err-unauthorized))
      (provider-id (get provider-id provider-lookup))
    )
    (asserts! (var-get program-active) err-invalid-data)
    (asserts! (and (>= pregnancy-stage u1) (<= pregnancy-stage u4)) err-invalid-stage)
    
    ;; Verify provider is authorized
    (let ((provider-info (unwrap! (map-get? providers { provider-id: provider-id }) err-not-found)))
      (asserts! (get is-verified provider-info) err-not-verified)
      
      ;; Verify patient exists and is assigned to this provider
      (let ((patient-info (unwrap! (map-get? patients { patient-id: patient-id }) err-not-found)))
        (asserts! (is-eq (get provider-id patient-info) provider-id) err-unauthorized)
        (asserts! (get is-active patient-info) err-invalid-data)
        
        ;; Check for duplicate checkup on same date
        (asserts! (is-none (map-get? patient-checkups { patient-id: patient-id, checkup-date: current-height })) err-checkup-exists)
        
        ;; Calculate rewards based on stage
        (let ((stage-reward (if (is-eq pregnancy-stage first-trimester)
                               first-trimester-reward
                               (if (is-eq pregnancy-stage second-trimester)
                                   second-trimester-reward
                                   (if (is-eq pregnancy-stage third-trimester)
                                       third-trimester-reward
                                       u0))))
              (screening-reward (* (len screenings-completed) screening-bonus))
              (total-reward (+ stage-reward screening-reward)))
          
          ;; Record checkup
          (map-set checkups
            { checkup-id: checkup-id }
            {
              patient-id: patient-id,
              provider-id: provider-id,
              checkup-date: current-height,
              pregnancy-stage: pregnancy-stage,
              week-of-pregnancy: week-of-pregnancy,
              checkup-type: checkup-type,
              vital-signs-normal: vital-signs-normal,
              screenings-completed: screenings-completed,
              notes: notes,
              rewards-earned: total-reward,
              is-verified: true
            })
          
          ;; Create patient checkup lookup
          (map-set patient-checkups
            { patient-id: patient-id, checkup-date: current-height }
            { checkup-id: checkup-id })
          
          ;; Update patient record
          (map-set patients
            { patient-id: patient-id }
            (merge patient-info {
              total-checkups: (+ (get total-checkups patient-info) u1),
              current-stage: pregnancy-stage,
              health-score: (if vital-signs-normal 
                               (if (> (+ (get health-score patient-info) u5) u100) u100 (+ (get health-score patient-info) u5))
                               (if (< (get health-score patient-info) u3) u0 (- (get health-score patient-info) u3)))
            }))
          
          ;; Update provider stats
          (map-set providers
            { provider-id: provider-id }
            (merge provider-info { total-checkups-verified: (+ (get total-checkups-verified provider-info) u1) }))
          
          ;; Update provider performance
          (let ((provider-stats-info (unwrap! (map-get? provider-stats { provider-id: provider-id }) err-not-found)))
            (map-set provider-stats
              { provider-id: provider-id }
              (merge provider-stats-info {
                monthly-checkups: (+ (get monthly-checkups provider-stats-info) u1),
                last-activity: current-height,
                performance-score: (if (> (+ (get performance-score provider-stats-info) u2) u100) u100 (+ (get performance-score provider-stats-info) u2))
              })))
          
          ;; Update milestone tracking
          (let ((milestone-info (unwrap! (map-get? patient-milestones { patient-id: patient-id }) err-not-found)))
            (map-set patient-milestones
              { patient-id: patient-id }
              (merge milestone-info {
                first-visit-completed: true,
                consistent-attendance: (+ (get consistent-attendance milestone-info) u1),
                all-screenings-completed: (>= (len screenings-completed) u3)
              })))
          
          ;; Update global counters
          (var-set next-checkup-id (+ checkup-id u1))
          (var-set total-checkups (+ (var-get total-checkups) u1))
          
          (ok { checkup-id: checkup-id, rewards-earned: total-reward })
        )
      )
    )
  )
)

;; Update patient milestone (for external rewards system)
(define-public (update-milestone 
  (patient-id uint) 
  (milestone-type (string-ascii 32)) 
  (value uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (let ((milestone-info (unwrap! (map-get? patient-milestones { patient-id: patient-id }) err-not-found)))
      (if (is-eq milestone-type "education")
        (begin
          (map-set patient-milestones
            { patient-id: patient-id }
            (merge milestone-info { education-sessions-attended: value }))
          (ok true))
        (if (is-eq milestone-type "referral")
          (begin
            (map-set patient-milestones
              { patient-id: patient-id }
              (merge milestone-info { referral-count: value }))
            (ok true))
          (ok false)))
    )
  )
)

;; Emergency functions
(define-public (deactivate-patient (patient-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (let ((patient-info (unwrap! (map-get? patients { patient-id: patient-id }) err-not-found)))
      (map-set patients
        { patient-id: patient-id }
        (merge patient-info { is-active: false }))
      (ok true)
    )
  )
)

(define-public (toggle-program-status)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set program-active (not (var-get program-active)))
    (ok (var-get program-active))
  )
)

;; read only functions

(define-read-only (get-patient-info (patient-id uint))
  (map-get? patients { patient-id: patient-id })
)

(define-read-only (get-patient-by-wallet (wallet principal))
  (match (map-get? patient-wallets { wallet: wallet })
    patient-lookup (map-get? patients { patient-id: (get patient-id patient-lookup) })
    none
  )
)

(define-read-only (get-provider-info (provider-id uint))
  (map-get? providers { provider-id: provider-id })
)

(define-read-only (get-provider-by-wallet (wallet principal))
  (match (map-get? provider-wallets { wallet: wallet })
    provider-lookup (map-get? providers { provider-id: (get provider-id provider-lookup) })
    none
  )
)

(define-read-only (get-checkup-info (checkup-id uint))
  (map-get? checkups { checkup-id: checkup-id })
)

(define-read-only (get-patient-milestones (patient-id uint))
  (map-get? patient-milestones { patient-id: patient-id })
)

(define-read-only (get-provider-stats (provider-id uint))
  (map-get? provider-stats { provider-id: provider-id })
)

(define-read-only (get-program-stats)
  {
    total-patients: (var-get total-patients),
    total-providers: (var-get total-providers),
    total-checkups: (var-get total-checkups),
    program-active: (var-get program-active),
    next-patient-id: (var-get next-patient-id),
    next-provider-id: (var-get next-provider-id)
  }
)

(define-read-only (calculate-patient-rewards (patient-id uint))
  (match (map-get? patients { patient-id: patient-id })
    patient-info
    (let ((milestone-info (default-to 
                            {
                              first-visit-completed: false,
                              early-registration-bonus: false,
                              consistent-attendance: u0,
                              all-screenings-completed: false,
                              education-sessions-attended: u0,
                              referral-count: u0,
                              total-milestone-rewards: u0
                            }
                            (map-get? patient-milestones { patient-id: patient-id }))))
      {
        base-checkup-rewards: (* (get total-checkups patient-info) u75), ;; Average reward
        milestone-rewards: (get total-milestone-rewards milestone-info),
        consistency-bonus: (* (get consistent-attendance milestone-info) u10),
        education-bonus: (* (get education-sessions-attended milestone-info) education-bonus),
        referral-bonus: (* (get referral-count milestone-info) u100)
      })
    { base-checkup-rewards: u0, milestone-rewards: u0, consistency-bonus: u0, education-bonus: u0, referral-bonus: u0 }
  )
)
