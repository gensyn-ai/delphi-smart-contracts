# ==========================================
# Shared flag plumbing
# ==========================================

.PHONY: deploy-delphi \
        deploy-truebit-oracle-relayer \
        deploy-timelock \
        create-market \
        get-block-timestamp \
        run-tests-with-coverage

# Targets that hit a live RPC / need a signer (interactive)
ONCHAIN_TARGETS := deploy-delphi \
                  deploy-truebit-oracle-relayer \
                  deploy-timelock \
                  create-market \
                  get-block-timestamp

# Targets where we want to force an explicit verification decision when broadcasting
VERIFY_REQUIRED_TARGETS := deploy-delphi \
                           deploy-truebit-oracle-relayer \
                           deploy-timelock

# Targets where verification should never be used
VERIFY_DISALLOWED_TARGETS := create-market

# If any selected goal is an onchain target, require NETWORK and enable signer prompting
ifneq ($(filter $(MAKECMDGOALS),$(ONCHAIN_TARGETS)),)

  # ===== REQUIRE NETWORK (no default) =====
  ifndef NETWORK
    $(error NETWORK is not set. Usage: make <target> NETWORK=<rpc-url-or-alias>)
  endif
  RPC_FLAG := --rpc-url $(NETWORK)

  # ===== ALWAYS REQUIRE A SIGNER (even for simulation) =====
  # forge script currently uses --interactives <N> for interactive key entry. :contentReference[oaicite:2]{index=2}
  SIGNER_FLAG := --interactives 1

  # ===== BROADCAST (default off) =====
  BROADCAST ?= 0
  ifeq ($(BROADCAST),1)
    BROADCAST_FLAG := --broadcast --slow
  else ifeq ($(BROADCAST),0)
    BROADCAST_FLAG :=
  else
    $(error BROADCAST must be 0 or 1)
  endif

  # ===== VERIFY (only for VERIFY_REQUIRED_TARGETS, only when BROADCAST=1) =====
  # Blockscout + Foundry wants verifier-url pointing to the explorer's /api/ endpoint. :contentReference[oaicite:3]{index=3}
  VERIFY_FLAG :=
  ifeq ($(BROADCAST),1)
    ifneq ($(filter $(MAKECMDGOALS),$(VERIFY_REQUIRED_TARGETS)),)

      # VERIFY is required when broadcasting deploy-ish targets (no default).
      ifndef VERIFY
        $(error VERIFY is not set. When BROADCAST=1 for $(filter $(MAKECMDGOALS),$(VERIFY_REQUIRED_TARGETS)), set VERIFY=1 (verify) or VERIFY=0 (skip).)
      endif

      # Allow overriding verifier URL explicitly.
      # Otherwise, infer from NETWORK when it matches a known alias.
      #
      # Testnet Blockscout instance: https://gensyn-testnet.explorer.alchemy.com (API at /api/). :contentReference[oaicite:4]{index=4}
      #
      # Mainnet default below assumes the same pattern. If yours differs, override:
      #   make ... VERIFIER_URL='https://<your-explorer>/api/'
      ifeq ($(NETWORK),gensyn-testnet)
        DEFAULT_VERIFIER_URL := https://gensyn-testnet.explorer.alchemy.com/api/
      else ifeq ($(NETWORK),gensyn-mainnet)
        DEFAULT_VERIFIER_URL := https://gensyn-mainnet.explorer.alchemy.com/api/
      else
        DEFAULT_VERIFIER_URL :=
      endif

      ifndef VERIFIER_URL
        VERIFIER_URL := $(DEFAULT_VERIFIER_URL)
      endif

      ifeq ($(VERIFY),1)
        ifeq ($(strip $(VERIFIER_URL)),)
          $(error VERIFIER_URL is not set. Set VERIFIER_URL=<blockscout_explorer_base>/api/)
        endif
        VERIFY_FLAG := --verify \
          --verifier blockscout \
          --verifier-url '$(VERIFIER_URL)'
      else ifeq ($(VERIFY),0)
        VERIFY_FLAG :=
      else
        $(error VERIFY must be 0 or 1)
      endif

    endif
  endif

  # ===== DISALLOW VERIFY on create-market =====
  # (unless you're also running a verify-required target in the same invocation)
  ifneq ($(filter $(MAKECMDGOALS),$(VERIFY_DISALLOWED_TARGETS)),)
    ifdef VERIFY
      ifeq ($(filter $(MAKECMDGOALS),$(VERIFY_REQUIRED_TARGETS)),)
        $(error VERIFY is not supported for $(filter $(MAKECMDGOALS),$(VERIFY_DISALLOWED_TARGETS)). Use BROADCAST=1 only.)
      endif
    endif
  endif

else
  RPC_FLAG :=
  SIGNER_FLAG :=
  BROADCAST_FLAG :=
  VERIFY_FLAG :=
endif

# ==========================================
#               TARGETS
# ==========================================

# ===== Deploy Delphi =====
deploy-delphi:
	forge script script/scripts/deployment/DeployDelphi.s.sol \
		$(RPC_FLAG) \
		$(SIGNER_FLAG) \
		$(BROADCAST_FLAG) \
		$(VERIFY_FLAG)

# ===== Deploy Truebit Oracle Relayer =====
deploy-truebit-oracle-relayer:
	forge script script/scripts/deployment/DeployTruebitOracleRelayer.s.sol \
		$(RPC_FLAG) \
		$(SIGNER_FLAG) \
		$(BROADCAST_FLAG) \
		$(VERIFY_FLAG)

# ===== Deploy Timelock =====
deploy-timelock:
	forge script script/scripts/deployment/DeployTimelock.s.sol \
		$(RPC_FLAG) \
		$(SIGNER_FLAG) \
		$(BROADCAST_FLAG) \
		$(VERIFY_FLAG)

# ===== Get Block Timestamp =====
get-block-timestamp:
	cast block latest $(RPC_FLAG) | grep timestamp

# ===== Create Market =====
create-market:
	forge script script/scripts/actions/CreateMarket.s.sol \
		$(RPC_FLAG) \
		$(SIGNER_FLAG) \
		$(BROADCAST_FLAG)

# ===== Coverage =====

# The invariant suite is the memory-heavy long pole under coverage instrumentation
# (optimizer + viaIR are disabled for accurate coverage), so running it alongside the
# fuzz suites OOM-kills the process. We shard the run: unit/fuzz tests in parallel, the
# invariant suite fully serialized on its own, then merge both tracefiles into a single
# unified lcov.info before generating the HTML report.
COVERAGE_INVARIANT_GLOB := test/invariant/**
# The fork suite requires a live RPC + ALCHEMY_API_KEY (see AGENTS.md); exclude it from
# the local coverage run so a missing key / offline network doesn't abort the shards.
COVERAGE_UNIT_EXCLUDE_GLOB := test/{invariant,fork}/**

run-tests-with-coverage: export FOUNDRY_PROFILE=coverage
run-tests-with-coverage:
	forge coverage --report lcov --report-file lcov-unit.info \
		--no-match-path '$(COVERAGE_UNIT_EXCLUDE_GLOB)' --threads 4
	forge coverage --report lcov --report-file lcov-invariant.info \
		--match-path '$(COVERAGE_INVARIANT_GLOB)' --threads 1
	lcov --add-tracefile lcov-unit.info \
		--add-tracefile lcov-invariant.info \
		--output-file lcov.info
	genhtml lcov.info --output-directory coverage
