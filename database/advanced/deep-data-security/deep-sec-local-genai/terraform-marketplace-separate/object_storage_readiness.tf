# OCI normally returns bucket creation only after the resource is available.
# During high-volume LiveLabs launches, verify both Stack-owned buckets through
# the Object Storage API before creating PARs or starting VM bootstrap. This is
# a bounded API readiness gate, not a fixed sleep: healthy buckets proceed
# immediately, while propagation or throttling receives time to recover.
resource "terraform_data" "object_storage_readiness" {
  input = {
    namespace            = data.oci_objectstorage_namespace.current.namespace
    wallet_bucket        = oci_objectstorage_bucket.wallet.name
    order_history_bucket = oci_objectstorage_bucket.order_history[0].name
  }

  triggers_replace = [
    oci_objectstorage_bucket.wallet.id,
    oci_objectstorage_bucket.order_history[0].id,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -Eeuo pipefail
      namespace='${self.input.namespace}'

      wait_for_bucket() {
        local bucket_name="$1"
        local attempt
        local error_file
        error_file=$(mktemp)
        trap 'rm -f "$error_file"' RETURN

        for attempt in $(seq 1 30); do
          if oci os bucket get \
              --namespace-name "$namespace" \
              --bucket-name "$bucket_name" \
              --output json > /dev/null 2> "$error_file"; then
            echo "Object Storage bucket is API-ready: $bucket_name"
            return 0
          fi

          echo "Bucket $bucket_name is not API-ready (attempt $attempt of 30); retrying in 10 seconds."
          sleep 10
        done

        echo "Object Storage bucket did not become API-ready: $bucket_name" >&2
        tail -n 20 "$error_file" >&2 || true
        return 1
      }

      wait_for_bucket '${self.input.wallet_bucket}'
      wait_for_bucket '${self.input.order_history_bucket}'
    EOT
  }
}
