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
    'installable': True,
    'application': True,
}