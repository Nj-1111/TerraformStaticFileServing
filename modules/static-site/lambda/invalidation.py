import boto3
import os

def handler(event, context):
    # The distribution ID is passed in as an environment variable
    # (Terraform sets this — the Lambda reads it here).
    distribution_id = os.environ['DISTRIBUTION_ID']

    # boto3 is AWS's Python SDK — this gives us a CloudFront client.
    client = boto3.client('cloudfront')

    # Ask CloudFront to invalidate everything ("/*").
    client.create_invalidation(
        DistributionId=distribution_id,
        InvalidationBatch={
            'Paths': {
                'Quantity': 1,
                'Items': ['/*']          # /* means "purge every cached file"
            },
            # CallerReference must be unique per call — a timestamp works.
            'CallerReference': str(context.aws_request_id)
        }
    )

    return {'statusCode': 200, 'body': 'Invalidation created'}