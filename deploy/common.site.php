<?php
/**
 * Site configuration for spejdernet.sondermark.dk, merged over the generated
 * common.php by deploy/entrypoint.d/10-common-config.sh on every start, for
 * both the web and the console application. Only what cannot be expressed in
 * deploy/humhub.<env>.env belongs here: PHP code such as closures. Scalar
 * configuration and pinned settings go in the .env file.
 */
return [
    'modules' => [
        'user' => [
            // Members are known by their scout name; show it first, with the
            // civil name in brackets, and fall back to the civil name.
            'displayNameCallback' => function (\humhub\modules\user\models\User $user) {
                return $user->profile->spejdernavn
                    ? "{$user->profile->spejdernavn} ({$user->profile->firstname} {$user->profile->lastname})"
                    : "{$user->profile->firstname} {$user->profile->lastname}";
            },
        ],
    ],
];
