/* Test oracle only. No production Bend code links this file or libcrypto.
 * Fresh X509 objects for every sample prevent X509_verify_cert's cached
 * signature success from turning repeated validation into a no-op. */
#define _POSIX_C_SOURCE 200809L
#include <openssl/x509.h>
#include <openssl/x509_vfy.h>
#include <openssl/x509v3.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void fail(const char *message) {
    fprintf(stderr, "%s\n", message);
    exit(1);
}

static uint64_t now(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) fail("clock failed");
    return (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

static X509 *read_certificate(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) fail("cannot open certificate");
    X509 *certificate = d2i_X509_fp(file, NULL);
    fclose(file);
    if (!certificate) fail("cannot parse DER certificate");
    return certificate;
}

/* chain COUNT EPOCH_SECONDS LEAF ANCHOR PEER...
 * signature COUNT ISSUER SUBJECT */
int main(int argc, char **argv) {
    if (argc < 5) fail("invalid arguments");
    int chain = !strcmp(argv[1], "chain");
    int count = atoi(argv[2]);
    if (count < 1 || (chain && argc < 6)) fail("invalid sample count/chain");
    for (int sample = 0; sample < count; sample++) {
        X509 *leaf = read_certificate(argv[4]);
        X509 *issuer = read_certificate(argv[chain ? 5 : 3]);
        X509_STORE *store = NULL;
        X509_STORE_CTX *context = NULL;
        STACK_OF(X509) *peers = NULL;
        if (chain) {
            store = X509_STORE_new();
            context = X509_STORE_CTX_new();
            peers = sk_X509_new_null();
            if (!store || !context || !peers || !X509_STORE_add_cert(store, issuer)) fail("store setup failed");
            for (int i = 6; i < argc; i++)
                if (!sk_X509_push(peers, read_certificate(argv[i]))) fail("peer setup failed");
        }
        uint64_t start = now();
        int result;
        if (chain) {
            if (!X509_STORE_CTX_init(context, store, leaf, peers)) fail("context setup failed");
            X509_VERIFY_PARAM *parameter = X509_STORE_CTX_get0_param(context);
            X509_VERIFY_PARAM_set_time(parameter, (time_t)strtoll(argv[3], NULL, 10));
            X509_VERIFY_PARAM_set_flags(parameter, X509_V_FLAG_PARTIAL_CHAIN | X509_V_FLAG_X509_STRICT);
            X509_VERIFY_PARAM_set_purpose(parameter, X509_PURPOSE_SSL_SERVER);
            result = X509_verify_cert(context);
        } else {
            EVP_PKEY *key = X509_get_pubkey(issuer);
            if (!key) fail("public key decoding failed");
            result = X509_verify(leaf, key);
            EVP_PKEY_free(key);
        }
        uint64_t duration = now() - start;
        if (result != 1) {
            if (chain) fprintf(stderr, "%s\n", X509_verify_cert_error_string(X509_STORE_CTX_get_error(context)));
            fail("verification failed");
        }
        printf("%llu\n", (unsigned long long)duration);
        X509_STORE_CTX_free(context);
        X509_STORE_free(store);
        sk_X509_pop_free(peers, X509_free);
        X509_free(leaf);
        X509_free(issuer);
    }
    return 0;
}
