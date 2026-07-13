<?php

declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

function is_root_cause_event(mixed $causeEventId): bool
{
    return $causeEventId === null ||
        $causeEventId === '' ||
        $causeEventId === '0' ||
        $causeEventId === 0 ||
        $causeEventId === false;
}

function has_non_zero_value(mixed $value): bool
{
    return $value !== null && $value !== '' && $value !== '0' && $value !== 0;
}

function is_enabled_status(mixed $status): bool
{
    return $status === null || $status === '' || (string)$status === '0';
}

function get_client_name(array $tags, array $groups, string $hostName): string
{
    $tagNames = ['cliente', 'client', 'customer', 'empresa', 'tenant'];
    foreach ($tags as $tag) {
        $tagName = strtolower(trim((string)($tag['tag'] ?? '')));
        $value = trim((string)($tag['value'] ?? ''));
        if (in_array($tagName, $tagNames, true) && $value !== '') {
            return $value;
        }
    }

    $ignored = [
        'templates',
        'linux servers',
        'windows servers',
        'zabbix servers',
        'discovered hosts',
        'network devices',
        'servidores',
        'clientes',
        'infraestrutura',
        'hypervisors',
        'switches',
        'firewalls',
        'roteadores',
        'appliances',
        'vmware',
        'snmp',
    ];

    foreach ($groups as $group) {
        $groupName = trim((string)($group['name'] ?? ''));
        if ($groupName !== '' && !in_array(strtolower($groupName), $ignored, true)) {
            return $groupName;
        }
    }

    if (str_contains($hostName, ' - ')) {
        return trim(explode(' - ', $hostName)[0]);
    }

    return $hostName;
}

function get_problems_with_fallback(array $params, string $apiUrl, string $token, string $fetchMode): array
{
    try {
        return zabbix_request('problem.get', $params, $apiUrl, $token);
    } catch (RuntimeException $error) {
        $message = $error->getMessage();
        $canFallback = $fetchMode === 'incidents' &&
            (str_contains($message, '/source') || str_contains($message, '/object') || str_contains($message, 'Invalid parameter'));

        if (!$canFallback) {
            throw $error;
        }

        unset($params['source'], $params['object']);

        return zabbix_request('problem.get', $params, $apiUrl, $token);
    }
}

try {
    $settings = settings_row();
    $apiUrl = trim((string)$settings['zabbix_api_url']);
    $token = decrypt_secret($settings['zabbix_token_encrypted'] ?? null);

    if ($apiUrl === '' || $token === '') {
        json_error('Configure a URL da API e o token do Zabbix no admin.', 424, [
            'config' => frontend_config_from_settings($settings),
        ]);
    }

    $fetchMode = (string)$settings['fetch_mode'];
    $problemParams = [
        'output' => [
            'eventid',
            'objectid',
            'name',
            'severity',
            'clock',
            'r_eventid',
            'r_clock',
            'acknowledged',
            'suppressed',
            'cause_eventid',
            'opdata',
        ],
        'selectTags' => 'extend',
        'severities' => [2, 3, 4, 5],
        'source' => 0,
        'object' => 0,
        'recent' => true,
        'suppressed' => false,
        'sortfield' => 'eventid',
        'sortorder' => 'DESC',
        'limit' => (int)$settings['api_limit'],
    ];

    $groupIds = decode_ids($settings['monitored_group_ids'] ?? '');
    $hostIds = decode_ids($settings['monitored_host_ids'] ?? '');
    if ($groupIds !== []) {
        $problemParams['groupids'] = $groupIds;
    }
    if ($hostIds !== []) {
        $problemParams['hostids'] = $hostIds;
    }

    $problems = get_problems_with_fallback($problemParams, $apiUrl, $token, $fetchMode);
    $rootProblems = $fetchMode === 'incidents'
        ? array_values(array_filter($problems, static fn($problem) => is_root_cause_event($problem['cause_eventid'] ?? null)))
        : $problems;

    $triggerIds = array_values(array_unique(array_filter(array_map(
        static fn($problem) => (string)($problem['objectid'] ?? ''),
        $rootProblems
    ))));

    $triggerMap = [];
    $hostMap = [];

    if ($triggerIds !== []) {
        $triggers = zabbix_request('trigger.get', [
            'output' => ['triggerid', 'description', 'priority', 'status'],
            'triggerids' => $triggerIds,
            'selectHosts' => ['hostid', 'host', 'name', 'status'],
            'selectItems' => ['itemid', 'name', 'key_', 'status'],
            'expandDescription' => true,
        ], $apiUrl, $token);

        foreach ($triggers as $trigger) {
            $triggerMap[(string)$trigger['triggerid']] = $trigger;
        }

        $resolvedHostIds = [];
        foreach ($triggers as $trigger) {
            foreach (($trigger['hosts'] ?? []) as $host) {
                if (!empty($host['hostid'])) {
                    $resolvedHostIds[] = (string)$host['hostid'];
                }
            }
        }
        $resolvedHostIds = array_values(array_unique($resolvedHostIds));

        if ($resolvedHostIds !== []) {
            try {
                $hosts = zabbix_request('host.get', [
                    'output' => ['hostid', 'host', 'name', 'status'],
                    'hostids' => $resolvedHostIds,
                    'selectHostGroups' => ['groupid', 'name'],
                ], $apiUrl, $token);
            } catch (RuntimeException) {
                $hosts = zabbix_request('host.get', [
                    'output' => ['hostid', 'host', 'name', 'status'],
                    'hostids' => $resolvedHostIds,
                    'selectGroups' => ['groupid', 'name'],
                ], $apiUrl, $token);
            }

            foreach ($hosts as $host) {
                $hostMap[(string)$host['hostid']] = $host;
            }
        }
    }

    $normalized = [];
    foreach ($rootProblems as $problem) {
        $trigger = $triggerMap[(string)($problem['objectid'] ?? '')] ?? null;
        if (!$trigger || !is_enabled_status($trigger['status'] ?? null)) {
            continue;
        }

        $hosts = $trigger['hosts'] ?? [];
        $disabledHost = false;
        foreach ($hosts as $host) {
            $enrichedHost = $hostMap[(string)($host['hostid'] ?? '')] ?? $host;
            if (!is_enabled_status($enrichedHost['status'] ?? null)) {
                $disabledHost = true;
                break;
            }
        }
        if ($disabledHost) {
            continue;
        }

        $disabledItem = false;
        foreach (($trigger['items'] ?? []) as $item) {
            if (!is_enabled_status($item['status'] ?? null)) {
                $disabledItem = true;
                break;
            }
        }
        if ($disabledItem) {
            continue;
        }

        $primaryHost = $hosts[0] ?? null;
        $host = $primaryHost ? ($hostMap[(string)($primaryHost['hostid'] ?? '')] ?? $primaryHost) : null;
        $hostName = $host ? (string)($host['name'] ?? $host['host'] ?? 'Host nao identificado') : 'Host nao identificado';
        $hostGroups = $host ? ($host['hostgroups'] ?? $host['groups'] ?? []) : [];
        $rClock = (int)($problem['r_clock'] ?? 0);

        $normalized[] = [
            'eventid' => (string)($problem['eventid'] ?? ''),
            'name' => (string)($problem['name'] ?? $trigger['description'] ?? 'Problema sem nome'),
            'severity' => (int)($problem['severity'] ?? 0),
            'clock' => (int)($problem['clock'] ?? 0),
            'rEventId' => (string)($problem['r_eventid'] ?? ''),
            'rClock' => $rClock,
            'acknowledged' => $problem['acknowledged'] ?? null,
            'suppressed' => $problem['suppressed'] ?? null,
            'causeEventId' => $problem['cause_eventid'] ?? null,
            'opdata' => (string)($problem['opdata'] ?? ''),
            'hostName' => $hostName,
            'clientName' => get_client_name($problem['tags'] ?? [], $hostGroups, $hostName),
            'status' => (has_non_zero_value($problem['r_eventid'] ?? null) || has_non_zero_value($problem['r_clock'] ?? null)) ? 'RESOLVIDO' : 'INCIDENTE',
        ];
    }

    json_response([
        'ok' => true,
        'problems' => $normalized,
        'ignoredInactiveCount' => count($rootProblems) - count($normalized),
        'config' => frontend_config_from_settings($settings),
        'syncedAt' => date(DATE_ATOM),
    ]);
} catch (Throwable $error) {
    handle_api_exception($error);
}
