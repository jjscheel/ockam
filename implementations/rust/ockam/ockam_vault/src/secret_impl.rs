use crate::software_vault::{SoftwareVault, VaultEntry};
use crate::VaultError;
use arrayref::array_ref;
use ockam_vault_core::{
    KeyIdVault, PublicKey, Secret, SecretAttributes, SecretKey, SecretPersistence, SecretType,
    SecretVault, AES128_SECRET_LENGTH, AES256_SECRET_LENGTH, CURVE25519_SECRET_LENGTH,
};
use rand::rngs::OsRng;
use rand::RngCore;
use zeroize::Zeroize;

impl SecretVault for SoftwareVault {
    /// Generate fresh secret. Only Curve25519 and Buffer types are supported
    fn secret_generate(&mut self, attributes: SecretAttributes) -> ockam_core::Result<Secret> {
        let mut rng = OsRng {};
        let (key, key_id) = match attributes.stype() {
            SecretType::Curve25519 => {
                let sk = x25519_dalek::StaticSecret::new(&mut rng);
                let public = x25519_dalek::PublicKey::from(&sk);
                let private = SecretKey::new(sk.to_bytes().to_vec());
                let key_id = self
                    .compute_key_id_for_public_key(&PublicKey::new(public.as_bytes().to_vec()))?;

                (private, Some(key_id))
            }
            SecretType::Buffer => {
                if attributes.persistence() != SecretPersistence::Ephemeral {
                    return Err(VaultError::InvalidKeyType.into());
                };
                let mut key = vec![0u8; attributes.length()];
                rng.fill_bytes(key.as_mut_slice());
                (SecretKey::new(key), None)
            }
            SecretType::Aes => {
                if attributes.length() != AES256_SECRET_LENGTH
                    && attributes.length() != AES128_SECRET_LENGTH
                {
                    return Err(VaultError::InvalidAesKeyLength.into());
                };
                if attributes.persistence() != SecretPersistence::Ephemeral {
                    return Err(VaultError::InvalidKeyType.into());
                };
                let mut key = vec![0u8; attributes.length()];
                rng.fill_bytes(&mut key);
                (SecretKey::new(key), None)
            }
            SecretType::P256 => {
                return Err(VaultError::InvalidKeyType.into());
            }
        };
        self.next_id += 1;
        self.entries
            .insert(self.next_id, VaultEntry::new(key_id, attributes, key));

        Ok(Secret::new(self.next_id))
    }

    fn secret_import(
        &mut self,
        secret: &[u8],
        attributes: SecretAttributes,
    ) -> ockam_core::Result<Secret> {
        // FIXME: Should we check secrets here?
        self.next_id += 1;
        self.entries.insert(
            self.next_id,
            VaultEntry::new(
                /* FIXME */ None,
                attributes,
                SecretKey::new(secret.to_vec()),
            ),
        );
        Ok(Secret::new(self.next_id))
    }

    fn secret_export(&mut self, context: &Secret) -> ockam_core::Result<SecretKey> {
        self.get_entry(context).map(|i| i.key().clone())
    }

    fn secret_attributes_get(&mut self, context: &Secret) -> ockam_core::Result<SecretAttributes> {
        self.get_entry(context).map(|i| i.key_attributes())
    }

    /// Extract public key from secret. Only Curve25519 type is supported
    fn secret_public_key_get(&mut self, context: &Secret) -> ockam_core::Result<PublicKey> {
        let entry = self.get_entry(context)?;

        if entry.key().as_ref().len() != CURVE25519_SECRET_LENGTH {
            return Err(VaultError::InvalidPrivateKeyLen.into());
        }

        match entry.key_attributes().stype() {
            SecretType::Curve25519 => {
                let sk = x25519_dalek::StaticSecret::from(*array_ref![
                    entry.key().as_ref(),
                    0,
                    CURVE25519_SECRET_LENGTH
                ]);
                let pk = x25519_dalek::PublicKey::from(&sk);
                Ok(PublicKey::new(pk.to_bytes().to_vec()))
            }
            _ => Err(VaultError::InvalidKeyType.into()),
        }
    }

    /// Remove secret from memory
    fn secret_destroy(&mut self, context: Secret) -> ockam_core::Result<()> {
        if let Some(mut k) = self.entries.remove(&context.index()) {
            k.zeroize();
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use crate::SoftwareVault;
    use ockam_vault_test_attribute::*;

    fn new_vault() -> SoftwareVault {
        SoftwareVault::default()
    }

    #[vault_test]
    fn new_public_keys() {}

    #[vault_test]
    fn new_secret_keys() {}

    #[vault_test]
    fn secret_import_export() {}

    #[vault_test]
    fn secret_attributes_get() {}
}
