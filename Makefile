#
# Copyright 2022 Kontain Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
TOP := $(shell git rev-parse --show-toplevel)

release:
	git tag ${TAG}
	git push origin ${TAG}
	gh auth login --with-token < ${TOKEN}
	gh release create v1.2.3 ${TAG}
	git tag -f current
	git push -f origin current