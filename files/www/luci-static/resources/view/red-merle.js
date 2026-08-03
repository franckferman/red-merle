'use strict';
'require view';
'require fs';
'require ui';

var isReadonlyView = !L.hasViewPermission() || null;

var STATUS_FIELDS = [
	[ 'modem_model',    _('Modem') ],
	[ 'modem_fw',       _('Firmware') ],
	[ 'imei',           _('IMEI') ],
	[ 'imsi',           _('IMSI') ],
	[ 'number',         _('Number') ],
	[ 'sim',            _('SIM') ],
	[ 'registration',   _('Registration') ],
	[ 'signal',         _('Signal') ],
	[ 'network',        _('Network') ],
	[ 'hardening_mode', _('Mode') ],
	[ 'lte_only',       _('LTE-only') ],
	[ 'gnss',           _('GNSS') ],
	[ 'supl_block',     _('SUPL block') ]
];

var BOOT_OPTIONS = [
	[ 'wipe_logs',       _('Wipe logs at boot/shutdown and after each IMEI change') ],
	[ 'randomize_mac',   _('Randomize upstream + AP MAC at boot') ],
	[ 'randomize_bssid', _('Randomize WiFi BSSIDs at boot') ],
	[ 'iptables_block',  _('Block SUPL/OMA-DM ports (kills IPsec NAT-T)') ],
	[ 'gps_hardening',   _('AT GPS hardening at boot (hardening mode only)') ]
];

var lastStatus = null;


function callRedMerle(args) {
	const cmd = '/usr/libexec/red-merle';
	var prom = fs.exec(cmd, args);
	return prom.then(
		function(res) {
			console.log('Red Merle args', args, 'res', res);
			if (res.code != 0) {
				throw new Error('Return code ' + res.code);
			} else {
				return res.stdout;
			}
		}
	).catch(
		function(err) {
			console.log('Error calling Red Merle', args, err);
			throw err;
		}
	);
}

function callRedMerleJson(args) {
	return callRedMerle(args).then(function(out) {
		try {
			return JSON.parse(out);
		} catch (e) {
			throw new Error('Invalid JSON response');
		}
	});
}

function readIMEI() {
	return callRedMerle(['read-imei']);
}

function readIMSI() {
	return callRedMerle(['read-imsi']);
}

function handleShutdown(ev) {
	return callRedMerle(['shutdown']);
}

function handleRestartModem(ev) {
	return callRedMerle(['shutdown-modem']).then(function(res) {
		ui.addNotification(null, E('p', _('Modem is restarting with the new IMEI…')), 'info');
		ui.hideModal();
	});
}

function setText(id, text) {
	var e = document.getElementById(id);
	if (e)
		e.textContent = text;
}

function updateStatus(data) {
	lastStatus = data;

	for (var i = 0; i < STATUS_FIELDS.length; i++)
		setText('rm-status-' + STATUS_FIELDS[i][0],
			(data && data[STATUS_FIELDS[i][0]] != null && data[STATUS_FIELDS[i][0]] !== '')
				? String(data[STATUS_FIELDS[i][0]]) : _('unknown'));

	setText('rm-state-hardening', data ? String(data.hardening_mode || _('unknown')) : _('unknown'));
	setText('rm-state-lte-only', data ? String(data.lte_only || _('unknown')) : _('unknown'));
	setText('rm-state-gps', data ? String(data.gnss || _('unknown')) : _('unknown'));

	for (var i = 0; i < BOOT_OPTIONS.length; i++) {
		var name = BOOT_OPTIONS[i][0];
		var val = (data && data.opts) ? data.opts[name] : null;
		setText('rm-opt-' + name, (val == 1) ? _('on') : _('off'));
	}
}

function refreshStatus(notify) {
	return callRedMerleJson(['status']).then(
		function(data) {
			updateStatus(data);
			if (notify)
				ui.addNotification(null, E('p', _('Status refreshed')), 'info');
		}
	).catch(
		function(err) {
			updateStatus(null);
			ui.addNotification(null, E('p', _('Unable to query red-merle status: ') + err), 'error');
		}
	);
}

function handleControl(action, onoff, label) {
	return callRedMerleJson([action, onoff]).then(
		function(res) {
			if (res && res.ok) {
				ui.addNotification(null, E('p', label + ': ' + onoff), 'info');
			} else {
				ui.addNotification(null, E('p', label + ': ' + ((res && res.error) || _('failed'))), 'error');
			}
			refreshStatus(false);
		}
	).catch(
		function(err) {
			ui.addNotification(null, E('p', label + ': ' + err), 'error');
			refreshStatus(false);
		}
	);
}

function handleBootOption(name) {
	var cur = (lastStatus && lastStatus.opts) ? lastStatus.opts[name] : 1;
	var next = (cur == 1) ? 0 : 1;
	return callRedMerleJson(['set-option', name, String(next)]).then(
		function(res) {
			if (res && res.ok) {
				ui.addNotification(null, E('p', name + ': ' + next), 'info');
			} else {
				ui.addNotification(null, E('p', name + ': ' + ((res && res.error) || _('failed'))), 'error');
			}
			refreshStatus(false);
		}
	).catch(
		function(err) {
			ui.addNotification(null, E('p', name + ': ' + err), 'error');
		}
	);
}

function refreshAtLog() {
	return callRedMerleJson(['at-log']).then(
		function(res) {
			var lines = (res && res.lines) ? res.lines : [];
			setText('rm-at-log', lines.length ? lines.join('\n') : _('(log is empty)'));
		}
	).catch(
		function(err) {
			setText('rm-at-log', _('Unable to read AT log: ') + err);
		}
	);
}

function controlRow(title, stateId, action, label) {
	return E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title' }, title),
		E('div', { 'class': 'cbi-value-field' }, [
			E('span', { 'id': stateId, 'style': 'font-weight:bold; margin-right:1em' }, _('unknown')),
			E('button', {
				'class': 'btn cbi-button-positive',
				'click': function(ev) { handleControl(action, 'on', label); },
				'disabled': isReadonlyView
			}, [ _('On') ]), ' ',
			E('button', {
				'class': 'btn cbi-button-negative',
				'click': function(ev) { handleControl(action, 'off', label); },
				'disabled': isReadonlyView
			}, [ _('Off') ])
		])
	]);
}

function handleSimSwap(ev) {
	const spinnerID = 'swap-spinner-id';
	var dlg = ui.showModal(_('Starting SIM swap...'),
	    [
			E('p', { 'class': 'spinning', 'id': spinnerID },
				_('Shutting down modem…')
			 )
		]
	);
    callRedMerle(['shutdown-modem']).then(
        function(res) {
            dlg.appendChild(
                E('pre', { 'class': 'result'},
                    res
                )
            );
            dlg.appendChild(
                E('p', { 'class': 'text'},
                    _("Generating Random IMEI")
                )
            );
            callRedMerle(['random-imei']).then(
                function(res) {
                    document.getElementById(spinnerID).style = "display:none";
                    dlg.appendChild(
                        E('div', { 'class': 'text'},
                          [
                            E('p', { 'class': 'text'},
                                _("IMEI set:") + " " + res
                            ),
                            E('p', { 'class': 'text'},
                                _("Swap the SIM, then restart the modem or shutdown the device. Go to another place before booting.")
                            ),
                            E('div', { 'style': 'display:flex; gap:0.6em; flex-wrap:wrap' }, [
                                E('button', { 'class': 'btn cbi-button-action', 'click': handleRestartModem, 'disabled': isReadonlyView },
                                    [ _('Restart modem…') ]
                                ),
                                E('button', { 'class': 'btn cbi-button-positive', 'click': handleShutdown, 'disabled': isReadonlyView },
                                    [ _('Shutdown…') ]
                                ),
                                E('button', { 'class': 'btn cbi-button-neutral', 'click': function(ev) { ui.hideModal(); } },
                                    [ _('Close') ]
                                )
                            ])
                          ]
                        )
                    )
                }
            ).catch(
                function(err) {
                    dlg.appendChild(
                        E('p',{'class': 'error'},
                            _('Error setting IMEI! ') + err
                        )
                    )
                }
            );
        }
    ).catch(
        function(err) {
            dlg.appendChild(
                E('p',{'class': 'error'},
                    _('Error! ') + err
                )
            )
        }
    );
}


return view.extend({
	load: function() {
		return callRedMerleJson(['status']).catch(function(err) {
			console.log('Error loading red-merle status', err);
			return null;
		});
	},

	render: function(statusData) {
        const imeiInputID = 'imei-input';
        const imsiInputID = 'imsi-input';

		var statusRows = [];
		for (var i = 0; i < STATUS_FIELDS.length; i++) {
			statusRows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'style': 'font-weight:bold; width:33%' }, STATUS_FIELDS[i][1]),
				E('td', { 'class': 'td left', 'id': 'rm-status-' + STATUS_FIELDS[i][0] }, _('unknown'))
			]));
		}

		var optionRows = [];
		for (var i = 0; i < BOOT_OPTIONS.length; i++) {
			(function(name, descr) {
				optionRows.push(E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, name),
					E('div', { 'class': 'cbi-value-field' }, [
						E('button', {
							'class': 'btn cbi-button',
							'id': 'rm-opt-' + name,
							'click': function(ev) { handleBootOption(name); },
							'disabled': isReadonlyView
						}, [ _('off') ]), ' ',
						E('span', { 'class': 'cbi-value-description', 'style': 'display:inline; margin-left:.5em' }, descr)
					])
				]));
			})(BOOT_OPTIONS[i][0], BOOT_OPTIONS[i][1]);
		}

		var view = E([], [
			E('h2', {}, _('Red Merle')),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Status')),
				E('div', { 'class': 'cbi-section-node' }, [
					E('table', { 'class': 'table' }, statusRows)
				]),
				E('div', { 'style': 'margin-top:.5em' }, [
					E('button', { 'class': 'btn cbi-button-action', 'click': function(ev) { refreshStatus(true); } }, [ _('Refresh') ])
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Controls')),
				E('div', { 'class': 'cbi-section-node' }, [
					controlRow(_('Hardening mode'), 'rm-state-hardening', 'hardening', _('Hardening')),
					controlRow(_('LTE-only'), 'rm-state-lte-only', 'lte-only', _('LTE-only')),
					controlRow(_('GNSS engine'), 'rm-state-gps', 'gps', _('GNSS'))
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Boot options')),
				E('div', { 'class': 'cbi-section-node' }, optionRows)
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('IMEI / SIM swap')),
				E('div', { 'class': 'cbi-section-node' }, [
					E('div', { 'class': 'cbi-value' }, [
						E('label', { 'class': 'cbi-value-title' }, _('IMEI')),
						E('div', { 'class': 'cbi-value-field' }, [
							E('input', { 'id': imeiInputID, 'type': 'text', 'disabled': true })
						])
					]),
					E('div', { 'class': 'cbi-value' }, [
						E('label', { 'class': 'cbi-value-title' }, _('IMSI')),
						E('div', { 'class': 'cbi-value-field' }, [
							E('input', { 'id': imsiInputID, 'type': 'text', 'disabled': true })
						])
					]),
					E('div', { 'class': 'cbi-value' }, [
						E('label', { 'class': 'cbi-value-title' }, _('Actions')),
						E('div', { 'class': 'cbi-value-field' }, [
							E('button', { 'class': 'btn cbi-button-positive', 'click': handleSimSwap, 'disabled': isReadonlyView }, [ _('SIM swap…') ])
						])
					])
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('AT command log')),
				E('div', { 'class': 'cbi-section-node' }, [
					E('pre', { 'id': 'rm-at-log', 'style': 'font-family:monospace; white-space:pre-wrap; word-break:break-all; max-height:24em; overflow:auto' }, _('(not loaded)')),
					E('div', {}, [
						E('button', { 'class': 'btn cbi-button-action', 'click': function(ev) { refreshAtLog(); } }, [ _('Refresh') ])
					])
				])
			])
		]);

		updateStatus(statusData);
		refreshAtLog();

		readIMEI().then(
		    function(imei) {
		        const e = document.getElementById(imeiInputID);
		        e.value = imei;
		    }
		).catch(
		    function(err){
		        console.log('Error: ', err)
		    }
		)

		readIMSI().then(
		    function(imsi) {
		        const e = document.getElementById(imsiInputID);
		        e.value = imsi;
		    }
		).catch(
		    function(err){
		        const e = document.getElementById(imsiInputID);
		        e.value = "No IMSI found";
		    }
		)

		return view;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
