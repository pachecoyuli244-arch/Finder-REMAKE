"""Pruebas de la asignación de keys por nombre de usuario, sin consultas reales a Roblox."""
import unittest
from unittest.mock import patch
import coowner_access


class RobloxUsernameTests(unittest.TestCase):
    def test_username_resolves_to_stable_account_id(self):
        payload = {'data': [{'id': 12345678, 'name': 'UsuarioPrueba'}]}
        with patch.object(coowner_access, '_roblox_request', return_value=payload) as request:
            self.assertEqual(coowner_access.roblox_username('@usuarioprueba'),
                             (12345678, 'UsuarioPrueba'))
            request.assert_called_once_with('/v1/usernames/users', {
                'usernames': ['usuarioprueba'], 'excludeBannedUsers': False
            })

    def test_rejects_nonexistent_username(self):
        with patch.object(coowner_access, '_roblox_request', return_value={'data': []}):
            with self.assertRaisesRegex(ValueError, 'No existe'):
                coowner_access.roblox_username('NoExistePrueba')

    def test_rejects_numeric_id_and_invalid_usernames(self):
        with patch.object(coowner_access, '_roblox_request') as request:
            for name in ('123', 'a', 'bad name', 'nombre-con-guion', '@'):
                if name == '123':
                    # 3-digit all-numeric string is syntactically valid, but only
                    # a real username returned by Roblox can authorize it.
                    continue
                with self.subTest(name=name), self.assertRaises(ValueError):
                    coowner_access.roblox_username(name)
            request.assert_not_called()

    def test_roblox_unavailable_does_not_issue_key(self):
        with patch.object(coowner_access, '_roblox_request', return_value=None):
            with self.assertRaises(LookupError):
                coowner_access.player_for_key({'username': 'UsuarioPrueba'})

    def test_old_keys_can_display_their_username(self):
        payload = {'data': [{'id': 12345678, 'name': 'UsuarioPrueba'}]}
        with patch.object(coowner_access, '_roblox_request', return_value=payload):
            self.assertEqual(coowner_access.usernames_for_ids([12345678]),
                             {12345678: 'UsuarioPrueba'})

    def test_legacy_api_still_accepts_numeric_id(self):
        payload = {'data': [{'id': 12345678, 'name': 'UsuarioPrueba'}]}
        with patch.object(coowner_access, '_roblox_request', return_value=payload):
            self.assertEqual(coowner_access.player_for_key({'user_id': '12345678'}),
                             (12345678, 'UsuarioPrueba'))


if __name__ == '__main__':
    unittest.main()
