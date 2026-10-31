# S02: the two-sided Lightning settlement record (offline)

`devcon8 s02` serves this folder; open http://127.0.0.1:8080/settlement-record.html.

One Lightning payment between two Mesh-LLM demo nodes, Shockley (payer) and Brattain (payee), on
2026-10-29 20:22 UTC: 1,000 msat sent, 995 received, 5 msat receive fee. Each node sealed its own half
under its own key. The page embeds the three leg records in `legs/` and checks them in your browser
with the Agent Action Capsule TypeScript verifier. It reads nothing from the network.
`screenshot-fallback.png` is the page as rendered.

The same legs through the CLI:

    cd /opt/devcon8/demos/s02/legs
    capsulectl settlement status --leg terms-shockley.json --leg payer_observed-shockley.json \
      --leg payee_observed-brattain.json \
      --payer-key b1ff0623566783ad73ece0cc4736788a4ad48c2dfce528ae18e165a49c2fd9e7 \
      --payee-key 5631608d05e1eee382e519abd6e93730a091a7334cbd5c33cb07f92af000b031

The two key ids are each node's own public key, not read from the legs. The page does not show the
nodes' checkpointed logs, and it cannot prove those keys are the nodes' real identities beyond what the
node operators state.
