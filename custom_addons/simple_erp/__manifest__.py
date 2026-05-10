{
    'name': 'Simple ERP System',
    'version': '1.0',
    'category': 'Operations',
    'summary': 'Manage Raw Products, Import CSV Sales, Upload Invoice Images, and Dashboard Reporting.',
    'depends': ['base', 'hr', 'hr_attendance'],
    'data': [
        'security/ir.model.access.csv',
        'views/views.xml',
    ],
    'assets': {
        'hr_attendance.assets_public_attendance': [
            'simple_erp/static/src/public_kiosk_exit_button.js',
            'simple_erp/static/src/public_kiosk_exit_button.scss',
        ],
    },
    'installable': True,
    'application': True,
}